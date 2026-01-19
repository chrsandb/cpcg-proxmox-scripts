#!/bin/bash

# Load configuration from .env
load_env() {
    local env_file=".env"
    if [[ ! -f "$env_file" ]]; then
        echo "Error: $env_file not found. Copy .env.template to .env and update values."
        exit 1
    fi
    # shellcheck disable=SC1091
    source "$env_file"
}

load_env

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROXMOX_API_URL=""
CSRF_TOKEN=""
PVE_AUTH_COOKIE=""
AUTH_HEADER_ARGS=()
DEBUG_MODE=false
INSECURE_TLS=false
CURL_OPTS=(-s)
VM_ID=""

# Function to print the help text
print_help() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --host <Proxmox Host>          Proxmox server IP or hostname (default: 192.168.1.6)"
  echo "  --user <Username>              Proxmox API username (default: root@pam)"
  echo "  --password <Password>          Proxmox API password (prompts if omitted; or set PVE_PASSWORD)"
  echo "  --node <Node Name>             Proxmox node name (default: pve)"
  echo "  --storage <Storage Name>       Proxmox storage name for ISO upload (default: from .env STORAGE_NAME_ISO)"
  echo "  --vm-id <VM ID>                ID of the VM to delete (required)"
  echo "  --ca-cert <Path>               Path to CA certificate for TLS validation (default: PVE_CACERT env)"
  echo "  --insecure                     Allow insecure TLS (self-signed). Not recommended."
  echo "  --debug                        Print API responses for debugging to STDERR"
  echo "  -h, --help                     Show this help message"
}

# Function to parse command-line arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --host) PVE_HOST="$2"; shift; shift ;;
      --user) PVE_USER="$2"; shift; shift ;;
      --password) PVE_PASSWORD="$2"; shift; shift ;;
      --node) NODE_NAME="$2"; shift; shift ;;
      --storage) STORAGE_NAME_ISO="$2"; shift; shift ;;
      --vm-id) VM_ID="$2"; shift; shift ;;
      --ca-cert) PVE_CACERT="$2"; shift; shift ;;
      --insecure) INSECURE_TLS=true; shift ;;
      --debug) DEBUG_MODE=true; shift ;;
      -h|--help) print_help; exit 0 ;;
      *) echo "Unknown option: $1"; print_help; exit 1 ;;
    esac
  done
}

# Validate required arguments
validate_arguments() {
  if [[ -z "$PVE_HOST" || -z "$PVE_USER" || -z "$NODE_NAME" || -z "$STORAGE_NAME_ISO" || -z "$VM_ID" ]]; then
    bail "$EXIT_USER" "Missing one or more required arguments (--host, --user, --node, --storage, --vm-id)."
  fi

  validate_ipv4_or_bail "$PVE_HOST" "--host"
  validate_numeric_or_bail "$VM_ID" "--vm-id"

  if [[ "$PVE_USER" != *@* ]]; then
    bail "$EXIT_USER" "Username must contain '@'. Example: root@pam"
  fi

  # Build the full Proxmox API URL
  PROXMOX_API_URL="https://$PVE_HOST:$PROXMOX_PORT/api2/json"
}

init_curl_opts() {
  CURL_OPTS=(-s)

  if [[ -n "$PVE_CACERT" ]]; then
    CURL_OPTS+=("--cacert" "$PVE_CACERT")
  fi

  if [[ "$INSECURE_TLS" == true ]]; then
    log_warn "TLS certificate validation disabled (--insecure). Use only in dev environments."
    CURL_OPTS+=("-k")
  fi
}

prompt_for_password() {
  read -s -p "Enter Proxmox password: " PVE_PASSWORD
  echo
}

# Function to authenticate and retrieve CSRF token and auth cookie
authenticate() {
  echo "Authenticating with Proxmox server..."
local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/access/ticket" \
    --data-urlencode "username=$PVE_USER" \
    --data-urlencode "password=$PVE_PASSWORD" \
    -H "Content-Type: application/x-www-form-urlencoded")

  debug_response "$response"

  CSRF_TOKEN=$(echo "$response" | jq -r '.data.CSRFPreventionToken')
  PVE_AUTH_COOKIE=$(echo "$response" | jq -r '.data.ticket')

  if [[ -z "$CSRF_TOKEN" || -z "$PVE_AUTH_COOKIE" ]]; then
    echo "Error: Authentication failed. Unable to retrieve CSRF token or auth cookie."
    exit 1
  fi
  echo "Authentication successful."
}

# Initialize auth headers for token or password auth
init_auth() {
  local auth_mode="$PVE_AUTH_MODE"
  if [[ -z "$auth_mode" ]]; then
    if [[ -n "$PVE_TOKEN_ID" && -n "$PVE_TOKEN_SECRET" ]]; then
      auth_mode="token"
    else
      auth_mode="password"
    fi
  fi

  if [[ "$auth_mode" == "token" ]]; then
    if [[ -z "$PVE_USER" || -z "$PVE_TOKEN_ID" || -z "$PVE_TOKEN_SECRET" ]]; then
      echo "Error: Token auth requires PVE_USER, PVE_TOKEN_ID, and PVE_TOKEN_SECRET."
      exit 1
    fi
    local token_id_full="$PVE_TOKEN_ID"
    if [[ "$token_id_full" != *"!"* ]]; then
      token_id_full="${PVE_USER}!${PVE_TOKEN_ID}"
    fi
    AUTH_HEADER_ARGS=(-H "Authorization: PVEAPIToken=${token_id_full}=${PVE_TOKEN_SECRET}")
  else
    if [[ -z "$PVE_PASSWORD" ]]; then
      prompt_for_password
    fi
    authenticate
    AUTH_HEADER_ARGS=(-H "CSRFPreventionToken: $CSRF_TOKEN" -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE")
  fi
}

# Function to debug API responses
debug_response() {
  local response="$1"
  if [[ "$DEBUG_MODE" == true ]]; then
    local redacted="$response"
    for secret in "$PVE_PASSWORD" "$PVE_TOKEN_SECRET" "$PVE_AUTH_COOKIE" "$CSRF_TOKEN"; do
      if [[ -n "$secret" ]]; then
        redacted=${redacted//"$secret"/"***REDACTED***"}
      fi
    done
    echo "API Response:" >&2
    echo "$redacted" | jq . >&2 || echo "$redacted" >&2
  fi
}

# Function to check if the VM exists
check_vm_exists() {
  echo "Checking if VM $VM_ID exists..."
  local response=$(curl_with_retries -X GET "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/status/current" \
    "${AUTH_HEADER_ARGS[@]}")

  debug_response "$response"

  local vm_status=$(echo "$response" | jq -r '.data.status // empty')
  if [[ -z "$vm_status" || "$vm_status" == "null" ]]; then
    echo "Error: VM $VM_ID does not exist."
    exit 1
  fi
  echo "VM $VM_ID exists with status: $vm_status."
}

# Function to retrieve the VM name
get_vm_name() {
  echo "Retrieving name for VM $VM_ID..."
  local response=$(curl_with_retries -X GET "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/config" \
    "${AUTH_HEADER_ARGS[@]}")

  debug_response "$response"

  local vm_name=$(echo "$response" | jq -r '.data.name // empty')
  if [[ -z "$vm_name" || "$vm_name" == "null" ]]; then
    echo "Error: Unable to retrieve the name for VM $VM_ID."
    exit 1
  fi

  echo "VM $VM_ID has name: $vm_name."
  VM_NAME="$vm_name"
}

# Function to hard stop a VM
stop_vm() {
  echo "Stopping VM $VM_ID..."
  local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/status/stop" \
    "${AUTH_HEADER_ARGS[@]}")

  debug_response "$response"

  local error=$(echo "$response" | jq -r '.errors // empty')
  if [[ $? -ne 0 || -n "$error" ]]; then
    echo "Error: Failed to stop the VM. Error details:"
    echo "$error"
    exit 1
  fi

  echo "Waiting for VM $VM_ID to stop..."
  while true; do
    local status_response=$(curl_with_retries -X GET "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/status/current" \
      "${AUTH_HEADER_ARGS[@]}")
    local vm_status=$(echo "$status_response" | jq -r '.data.status')

    if [[ "$vm_status" == "stopped" ]]; then
      echo "VM $VM_ID has stopped."
      break
    fi

    sleep 2
  done
}

# Function to delete a VM
delete_vm() {
  echo "Deleting VM $VM_ID..."
  local response=$(curl_with_retries -X DELETE "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID" \
    "${AUTH_HEADER_ARGS[@]}")

  debug_response "$response"

  local error=$(echo "$response" | jq -r '.errors // empty')
  if [[ $? -ne 0 || -n "$error" ]]; then
    echo "Error: Failed to delete the VM. Error details:"
    echo "$error"
    exit 1
  fi

  echo "VM $VM_ID deleted successfully."
}

# Function to delete the associated ISO
delete_iso() {
  local iso_filename="CI_${VM_ID}_${VM_NAME}.iso"
  echo "Deleting ISO $iso_filename from storage $STORAGE_NAME_ISO..."
  local response=$(curl_with_retries -X DELETE "$PROXMOX_API_URL/nodes/$NODE_NAME/storage/$STORAGE_NAME_ISO/content/$STORAGE_NAME_ISO:iso/$iso_filename" \
    "${AUTH_HEADER_ARGS[@]}")

  debug_response "$response"

  local error=$(echo "$response" | jq -r '.errors // empty')
  if [[ $? -ne 0 || -n "$error" ]]; then
    echo "Error: Failed to delete the ISO. Error details:"
    echo "$error"
    exit 1
  fi

  echo "ISO $iso_filename deleted successfully."
}

# Main script execution
main() {
  setup_traps
  parse_arguments "$@"
  validate_arguments
  init_curl_opts
  init_auth
  check_vm_exists
  get_vm_name
  stop_vm
  delete_vm
  delete_iso
  log_info "VM and associated ISO deleted successfully."
}

# Run the main function
main "$@"
