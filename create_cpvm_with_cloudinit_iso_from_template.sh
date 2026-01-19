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
VM_ID=""
DEBUG_MODE=false
INSECURE_TLS=false
CURL_OPTS=(-s)

# Function to print the help text
print_help() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --host <Proxmox Host>          Proxmox server IP or hostname (default: 192.168.1.12)"
  echo "  --user <Username>              Proxmox API username (default: root@pam)"
  echo "  --password <Password>          Proxmox API password (prompts if omitted; or set PVE_PASSWORD)"
  echo "  --node <Node Name>             Proxmox node name (default: pve02)"
  echo "  --storage <Storage Name>       Proxmox storage name for ISO upload (default: from .env STORAGE_NAME_ISO)"
  echo "  --template <Template ID>       Template VM ID (default: from .env CPVM_TEMPLATE_VM_ID)"
  echo "  --resize <Disk Resize>         Disk resize value (default: from .env CPVM_DISK_RESIZE)"
  echo "  --name <VM Name>               Name of the new VM (default: from .env CPVM_VM_NAME)"
  echo "  --start-id <Start VM ID>       Start searching for VM ID from this value (default: from .env CPVM_VM_ID_START)"
  echo "  --user-data <User Data File>   Path to the Cloud-Init user_data file (default: from .env CPVM_USER_DATA_FILE)"
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
      --template) CPVM_TEMPLATE_VM_ID="$2"; shift; shift ;;
      --resize) CPVM_DISK_RESIZE="$2"; shift; shift ;;
      --name) CPVM_VM_NAME="$2"; shift; shift ;;
      --start-id) CPVM_VM_ID_START="$2"; shift; shift ;;
      --user-data) CPVM_USER_DATA_FILE="$2"; shift; shift ;;
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
  if [[ -z "$CPVM_USER_DATA_FILE" ]]; then
    bail "$EXIT_USER" "--user-data argument is required and must point to a valid file."
  fi

  require_file_readable "$CPVM_USER_DATA_FILE" "--user-data"

  if [[ -z "$PVE_HOST" || -z "$PVE_USER" || -z "$NODE_NAME" || -z "$STORAGE_NAME_ISO" ]]; then
    bail "$EXIT_USER" "Missing one or more required arguments (--host, --user, --node, --storage)."
  fi

  validate_ipv4_or_bail "$PVE_HOST" "--host"
  validate_numeric_or_bail "$CPVM_TEMPLATE_VM_ID" "--template"
  validate_numeric_or_bail "$CPVM_VM_ID_START" "--start-id"
  validate_disk_resize_or_bail "$CPVM_DISK_RESIZE" "--resize"

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

# Function to find the next available VM ID
get_available_vm_id() {
  local max_attempts=100
  local attempts=0
  local current_id=$CPVM_VM_ID_START

  while (( attempts < max_attempts )); do
    local response=$(curl_with_retries -X GET "$PROXMOX_API_URL/cluster/nextid?vmid=$current_id" \
      "${AUTH_HEADER_ARGS[@]}")

    debug_response "$response"

    local vm_id=$(echo "$response" | jq -r '.data')
    if [[ -n "$vm_id" && "$vm_id" != "null" ]]; then
      VM_ID="$vm_id"
      return 0
    fi

    (( attempts++ ))
    (( current_id++ ))
  done

  echo "Error: Unable to find an available VM ID after $max_attempts attempts." >&2
  exit 1
}

# Function to create a Cloud-Init ISO
create_cloudinit_iso() {
  echo "Creating Cloud-Init ISO..."
  mkdir -p "$CPVM_TEMP_ISO_DIR"
  mkdir -p "$CPVM_TEMP_FS_DIR/openstack/2015-10-15"

  cp "$CPVM_USER_DATA_FILE" "$CPVM_TEMP_FS_DIR/openstack/2015-10-15/user_data"

  local iso_filename="CI_${VM_ID}_${CPVM_VM_NAME}.iso"
  mkisofs -r -J -jcharset utf-8 -V config-2 -o "$CPVM_TEMP_ISO_DIR/$iso_filename" "$CPVM_TEMP_FS_DIR" > /dev/null 2>&1

  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to create Cloud-Init ISO."
    rm -rf "$CPVM_TEMP_FS_DIR" "$CPVM_TEMP_ISO_DIR"
    exit 1
  fi

  rm -rf "$CPVM_TEMP_FS_DIR"
  echo "Cloud-Init ISO created at $CPVM_TEMP_ISO_DIR/$iso_filename."
}

# Function to upload the ISO
upload_iso() {
  local iso_filename="CI_${VM_ID}_${CPVM_VM_NAME}.iso"
  echo "Uploading Cloud-Init ISO ($iso_filename) to Proxmox storage ($STORAGE_NAME_ISO)..."
  local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/storage/$STORAGE_NAME_ISO/upload" \
    "${AUTH_HEADER_ARGS[@]}" \
    -F "content=iso" \
    -F "filename=@$CPVM_TEMP_ISO_DIR/$iso_filename")

  debug_response "$response"

  local error=$(echo "$response" | jq -r '.errors // empty')
  if [[ $? -ne 0 || -n "$error" ]]; then
    echo "Error: Failed to upload Cloud-Init ISO. Error details:"
    echo "$error"
    exit 1
  fi

  rm -rf "$CPVM_TEMP_ISO_DIR"
  echo "Cloud-Init ISO uploaded and temporary ISO folder cleaned up successfully."
}

# Function to clone a VM from the template
clone_vm() {
  echo "Cloning template VM ($CPVM_TEMPLATE_VM_ID) to create VM ($VM_ID)..."
  local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$CPVM_TEMPLATE_VM_ID/clone" \
    "${AUTH_HEADER_ARGS[@]}" \
    --data-urlencode "newid=$VM_ID" \
    --data-urlencode "name=$CPVM_VM_NAME")

  debug_response "$response"

  local error=$(echo "$response" | jq -r '.errors // empty')
  if [[ $? -ne 0 || -n "$error" ]]; then
    echo "Error: Failed to clone the VM. Error details:"
    echo "$error"
    exit 1
  fi

  echo "VM cloned successfully."
}

# Function to resize the VM disk
resize_disk() {
  echo "Resizing disk for VM $VM_ID..."
  local response=$(curl_with_retries -X PUT "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/resize" \
    "${AUTH_HEADER_ARGS[@]}" \
    --data-urlencode "disk=scsi0" \
    --data-urlencode "size=$CPVM_DISK_RESIZE")

  debug_response "$response"

  local success=$(echo "$response" | jq -r '.data // empty')
  if [[ -z "$success" || "$success" == "null" ]]; then
    echo "Error: Failed to resize the disk. Possible reasons:"
    echo "  - Ensure the disk is in a resizable format (e.g., qcow2 or raw)."
    echo "  - Verify the size parameter syntax (e.g., +80G)."
    echo "  - Check Proxmox user permissions for resizing disks."
    echo "Error details: $response"
    exit 1
  fi

  echo "Disk resized successfully to $CPVM_DISK_RESIZE."
}

# Function to attach the ISO to the VM
attach_iso() {
  echo "Attaching Cloud-Init ISO to VM $VM_ID..."
  local iso_filename="CI_${VM_ID}_${CPVM_VM_NAME}.iso"
  local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/config" \
    "${AUTH_HEADER_ARGS[@]}" \
    --data-urlencode "ide2=$STORAGE_NAME_ISO:iso/$iso_filename,media=cdrom")

  debug_response "$response"

  local error=$(echo "$response" | jq -r '.errors // empty')
  if [[ $? -ne 0 || -n "$error" ]]; then
    echo "Error: Failed to attach ISO to the VM. Error details:"
    echo "$error"
    exit 1
  fi

  echo "Cloud-Init ISO attached successfully."
}

# Main script execution
main() {
  setup_traps
  parse_arguments "$@"
  validate_arguments
  init_curl_opts
  init_auth
  get_available_vm_id
  create_cloudinit_iso
  upload_iso
  clone_vm
  resize_disk
  attach_iso
  log_info "VM creation and configuration completed successfully!"
}

# Run the main function
main "$@"
