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

# Function to print the help text
print_help() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --host <Proxmox Host>          Proxmox server IP or hostname (default: 192.168.1.21)"
  echo "  --user <Username>              Proxmox API username (default: root@pam)"
  echo "  --password <Password>          Proxmox API password (prompts if omitted; or set PVE_PASSWORD)"
  echo "  --node <Node Name>             Proxmox node name (default: pve)"
  echo "  --storage <Storage Name>       Proxmox storage name (default: from .env STORAGE_NAME_DISK)"
  echo "  --template-id <Template ID>    VM ID for the template (default: from .env CPMNGT_TEMPLATE_ID)"
  echo "  --template-name <Template Name> VM name for the template (default: from .env CPMNGT_TEMPLATE_NAME)"
  echo "  --cores <Cores>                Number of CPU cores (default: from .env CPMNGT_CORES)"
  echo "  --memory <Memory>              Memory size in MB (default: from .env CPMNGT_MEMORY)"
  echo "  --bridge <Bridge>              Network bridge (default: from .env CPMNGT_BRIDGE)"
  echo "  --qcow2_image <QCOW2 File>     QCOW2 file path (default: from .env CPMNGT_QCOW2_IMAGE)"
  echo "  --copy-image                   Copy the QCOW2 file to the Proxmox server"
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
      --storage) STORAGE_NAME_DISK="$2"; shift; shift ;;
      --template-id) CPMNGT_TEMPLATE_ID="$2"; shift; shift ;;
      --template-name) CPMNGT_TEMPLATE_NAME="$2"; shift; shift ;;
      --cores) CPMNGT_CORES="$2"; shift; shift ;;
      --memory) CPMNGT_MEMORY="$2"; shift; shift ;;
      --bridge) CPMNGT_BRIDGE="$2"; shift; shift ;;
      --qcow2_image) CPMNGT_QCOW2_IMAGE="$2"; shift; shift ;;
      --copy-image) CPMNGT_COPY_IMAGE=true; shift ;;
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
  if [[ -z "$CPMNGT_QCOW2_IMAGE" || (! -f "$CPMNGT_QCOW2_IMAGE" && "$CPMNGT_COPY_IMAGE" == true) ]]; then
    bail "$EXIT_USER" "--qcow2_image is required and must point to a valid QCOW2 file when copying."
  fi

  if [[ -z "$PVE_HOST" || -z "$PVE_USER" || -z "$NODE_NAME" || -z "$STORAGE_NAME_DISK" ]]; then
    bail "$EXIT_USER" "Missing one or more required arguments (--host, --user, --node, --storage)."
  fi

  validate_ipv4_or_bail "$PVE_HOST" "--host"
  validate_numeric_or_bail "$CPMNGT_TEMPLATE_ID" "--template-id"
  validate_numeric_or_bail "$CPMNGT_CORES" "--cores"
  validate_numeric_or_bail "$CPMNGT_MEMORY" "--memory"

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

# Wait for a Proxmox task to complete and validate exit status
wait_for_task() {
  local upid="$1"
  local task_name="$2"
  local timeout=300
  local interval=5
  local elapsed=0

  if [[ -z "$upid" || "$upid" == "null" ]]; then
    echo "Error: Missing task ID for $task_name."
    exit 1
  fi

  while (( elapsed < timeout )); do
    local response=$(curl_with_retries -X GET "$PROXMOX_API_URL/nodes/$NODE_NAME/tasks/$upid/status" \
      "${AUTH_HEADER_ARGS[@]}")

    debug_response "$response"

    local status=$(echo "$response" | jq -r '.data.status // empty')
    local exitstatus=$(echo "$response" | jq -r '.data.exitstatus // empty')

    if [[ "$status" == "stopped" ]]; then
      if [[ "$exitstatus" != "OK" ]]; then
        echo "Error: Task $task_name failed with status: $exitstatus"
        exit 1
      fi
      return 0
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  echo "Error: Timeout waiting for task $task_name to complete."
  exit 1
}

# Function to SCP the QCOW2 file
scp_qcow2_image() {
  if $CPMNGT_COPY_IMAGE; then
    echo "Transferring QCOW2 image to Proxmox server..."
    scp "$CPMNGT_QCOW2_IMAGE" "$PVE_USER@$PVE_HOST:$CPMNGT_IMAGE_PATH"
    if [[ $? -ne 0 ]]; then
      echo "Error: Failed to transfer QCOW2 file to Proxmox server."
      exit 1
    fi
    echo "QCOW2 image transferred successfully."
  else
    echo "Skipping QCOW2 file transfer as --copy-image was not specified."
  fi
}

# Function to create a new VM for the template
create_vm() {
  echo "Creating VM $CPMNGT_TEMPLATE_ID for the template..."
  local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu" \
    "${AUTH_HEADER_ARGS[@]}" \
    --data-urlencode "vmid=$CPMNGT_TEMPLATE_ID" \
    --data-urlencode "name=$CPMNGT_TEMPLATE_NAME" \
    --data-urlencode "cores=$CPMNGT_CORES" \
    --data-urlencode "memory=$CPMNGT_MEMORY" \
    --data-urlencode "net0=virtio,bridge=$CPMNGT_BRIDGE" \
    --data-urlencode "scsihw=virtio-scsi-pci")

  debug_response "$response"

  local error=$(echo "$response" | jq -r '.errors // empty')
  if [[ $? -ne 0 || -n "$error" ]]; then
    echo "Error: Failed to create VM. Error details:"
    echo "$error"
    exit 1
  fi
  echo "VM created successfully."
}

# Function to wait for scsi0 disk to exist
wait_for_scsi0_disk() {
  echo "Waiting for scsi0 disk to be available for VM $CPMNGT_TEMPLATE_ID..."
  local timeout=120  # Timeout in seconds
  local interval=5   # Interval between checks
  local elapsed=0

  while (( elapsed < timeout )); do
    local response=$(curl_with_retries -X GET "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$CPMNGT_TEMPLATE_ID/config" \
      "${AUTH_HEADER_ARGS[@]}")

    debug_response "$response"

    local scsi0=$(echo "$response" | jq -r '.data.scsi0 // empty')
    if [[ -n "$scsi0" ]]; then
      echo "scsi0 disk is available for VM $CPMNGT_TEMPLATE_ID."
      return 0
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  echo "Error: Timeout waiting for scsi0 disk to be available for VM $CPMNGT_TEMPLATE_ID."
  exit 1
}

# Function to import the QCOW2 image
import_qcow2_image() {
  echo "Importing QCOW2 image into the VM..."
  local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$CPMNGT_TEMPLATE_ID/config" \
    "${AUTH_HEADER_ARGS[@]}" \
    --data-urlencode "scsi0=$STORAGE_NAME_DISK:0,import-from=$CPMNGT_IMAGE_PATH$(basename "$CPMNGT_QCOW2_IMAGE")")

  debug_response "$response"

  local upid=$(echo "$response" | jq -r '.data // empty')
  local error=$(echo "$response" | jq -r '.errors // empty')
  if [[ $? -ne 0 || -n "$error" ]]; then
    echo "Error: Failed to import QCOW2 image. Error details:"
    echo "$error"
    exit 1
  fi

  wait_for_task "$upid" "import_qcow2_image"
  wait_for_scsi0_disk  # Ensure scsi0 disk is ready before proceeding

  echo "QCOW2 image imported successfully."
}

# Function to configure the VM for templating
configure_vm() {
  echo "Configuring VM $CPMNGT_TEMPLATE_ID for template creation..."
  local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$CPMNGT_TEMPLATE_ID/config" \
    "${AUTH_HEADER_ARGS[@]}" \
    --data-urlencode "boot=order=scsi0" \
    --data-urlencode "serial0=socket" \
    --data-urlencode "vga=serial0" \
    --data-urlencode "agent=enabled=1,type=isa")

  debug_response "$response"

  local error=$(echo "$response" | jq -r '.errors // empty')
  if [[ $? -ne 0 || -n "$error" ]]; then
    echo "Error: Failed to configure the VM. Error details:"
    echo "$error"
    exit 1
  fi
  echo "VM configured successfully."
}

# Function to convert the VM to a template
convert_to_template() {
  echo "Converting VM $CPMNGT_TEMPLATE_ID to a template..."
  local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$CPMNGT_TEMPLATE_ID/template" \
    "${AUTH_HEADER_ARGS[@]}")

  debug_response "$response"

  local error=$(echo "$response" | jq -r '.errors // empty')
  if [[ $? -ne 0 || -n "$error" ]]; then
    echo "Error: Failed to convert VM to a template. Error details:"
    echo "$error"
    exit 1
  fi
  echo "VM converted to template successfully."
}

# Main script execution
main() {
  setup_traps
  parse_arguments "$@"
  validate_arguments
  init_curl_opts
  init_auth
  scp_qcow2_image
  create_vm
  import_qcow2_image
  configure_vm
  convert_to_template
  log_info "Template creation completed successfully!"
}

# Run the main function
main "$@"
