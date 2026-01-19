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
  read -rs -p "Enter Proxmox password: " PVE_PASSWORD
  echo
}

check_vm_exists() {
  log_info "Checking if VM $VM_ID exists..."
  local response=$(curl_with_retries -X GET "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/status/current" \
    "${AUTH_HEADER_ARGS[@]}")

  debug_response "$response"

  local vm_status=$(get_jq_data "$response" '.data.status')
  if [[ -z "$vm_status" || "$vm_status" == "null" ]]; then
    bail "$EXIT_API" "VM $VM_ID does not exist."
  fi
  log_info "VM $VM_ID exists with status: $vm_status."
}

# Function to retrieve the VM name
get_vm_name() {
  local response=$(curl_with_retries -X GET "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/config" \
    "${AUTH_HEADER_ARGS[@]}")

  debug_response "$response"

  VM_NAME=$(get_jq_data "$response" '.data.name')
  if [[ -z "$VM_NAME" || "$VM_NAME" == "null" ]]; then
    bail "$EXIT_API" "Unable to retrieve the name for VM $VM_ID."
  fi

  log_info "VM $VM_ID has name: $VM_NAME."
}

# Function to hard stop a VM
stop_vm() {
  log_info "Stopping VM $VM_ID..."
  local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/status/stop" \
    "${AUTH_HEADER_ARGS[@]}")

  debug_response "$response"

  check_api_error "$response" "stop the VM"

  wait_for_vm_status "$VM_ID" "stopped"
  log_info "VM $VM_ID has stopped."
}

# Function to delete a VM
delete_vm() {
  echo "Deleting VM $VM_ID..."
  local response=$(curl_with_retries -X DELETE "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID" \
    "${AUTH_HEADER_ARGS[@]}")

  debug_response "$response"

  check_api_error "$response" "delete the VM"

  echo "VM $VM_ID deleted successfully."
}

# Function to delete the associated ISO
delete_iso() {
  local iso_filename="CI_${VM_ID}_${VM_NAME}.iso"
  echo "Deleting ISO $iso_filename from storage $STORAGE_NAME_ISO..."
  local response=$(curl_with_retries -X DELETE "$PROXMOX_API_URL/nodes/$NODE_NAME/storage/$STORAGE_NAME_ISO/content/$STORAGE_NAME_ISO:iso/$iso_filename" \
    "${AUTH_HEADER_ARGS[@]}")

  debug_response "$response"

  check_api_error "$response" "delete the ISO"

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
