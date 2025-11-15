#!/bin/bash

# Default Variables
PVE_HOST="10.17.1.12"
PVE_USER="root@pam"
PVE_PASSWORD=""
NODE_NAME="pve02"
STORAGE_NAME="media"
TEMPLATE_VM_ID=9500
DISK_RESIZE="+80G"
VM_NAME="mynewvm"
VM_ID_START=501
TEMP_ISO_DIR="/tmp/iso"
TEMP_FS_DIR="/tmp/fs"
USER_DATA_FILE=""
PROXMOX_PORT="8006"
PROXMOX_API_URL=""
DEBUG_MODE=false

CSRF_TOKEN=""
PVE_AUTH_COOKIE=""
VM_ID=""

# Function to print the help text
print_help() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --host <Proxmox Host>          Proxmox server IP or hostname (default: 10.17.1.12)"
  echo "  --user <Username>              Proxmox API username (default: root@pam)"
  echo "  --password <Password>          Proxmox API password (required)"
  echo "  --node <Node Name>             Proxmox node name (default: pve02)"
  echo "  --storage <Storage Name>       Proxmox storage name for ISO upload (default: media)"
  echo "  --template <Template ID>       Template VM ID (default: 9500)"
  echo "  --resize <Disk Resize>         Disk resize value (default: +80G)"
  echo "  --name <VM Name>               Name of the new VM (default: mynewvm)"
  echo "  --start-id <Start VM ID>       Start searching for VM ID from this value (default: 501)"
  echo "  --user-data <User Data File>   Path to the Cloud-Init user_data file (required)"
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
      --storage) STORAGE_NAME="$2"; shift; shift ;;
      --template) TEMPLATE_VM_ID="$2"; shift; shift ;;
      --resize) DISK_RESIZE="$2"; shift; shift ;;
      --name) VM_NAME="$2"; shift; shift ;;
      --start-id) VM_ID_START="$2"; shift; shift ;;
      --user-data) USER_DATA_FILE="$2"; shift; shift ;;
      --debug) DEBUG_MODE=true; shift ;;
      -h|--help) print_help; exit 0 ;;
      *) echo "Unknown option: $1"; print_help; exit 1 ;;
    esac
  done
}

# Validate required arguments
validate_arguments() {
  if [[ -z "$USER_DATA_FILE" ]]; then
    echo "Error: --user-data argument is required and must point to a valid file."
    print_help
    exit 1
  fi

  if [[ ! -f "$USER_DATA_FILE" ]]; then
    echo "Error: The file specified by --user-data does not exist: $USER_DATA_FILE"
    exit 1
  fi

  if [[ -z "$PVE_HOST" || -z "$PVE_USER" || -z "$PVE_PASSWORD" || -z "$NODE_NAME" || -z "$STORAGE_NAME" ]]; then
    echo "Error: Missing one or more required arguments (--host, --user, --password, --node, --storage)."
    print_help
    exit 1
  fi

  if [[ "$PVE_USER" != *@* ]]; then
    echo "Error: Username must contain '@'. Example: root@pam"
    exit 1
  fi

  # Build the full Proxmox API URL
  PROXMOX_API_URL="https://$PVE_HOST:$PROXMOX_PORT/api2/json"
}

# Function to authenticate and retrieve CSRF token and auth cookie
authenticate() {
  echo "Authenticating with Proxmox server..."
  local response=$(curl -s -k -X POST "$PROXMOX_API_URL/access/ticket" \
    --data-urlencode "username=$PVE_USER" \
    --data-urlencode "password=$PVE_PASSWORD" \
    -H "Content-Type: application/x-www-form-urlencoded")

  if $DEBUG_MODE; then
    echo "Authentication Response:" >&2
    echo "$response" | jq . >&2 || echo "$response" >&2
  fi

  CSRF_TOKEN=$(echo "$response" | jq -r '.data.CSRFPreventionToken')
  PVE_AUTH_COOKIE=$(echo "$response" | jq -r '.data.ticket')

  if [[ -z "$CSRF_TOKEN" || -z "$PVE_AUTH_COOKIE" || "$CSRF_TOKEN" == "null" ]]; then
    echo "Error: Authentication failed. Unable to retrieve CSRF token or auth cookie."
    exit 1
  fi
  echo "Authentication successful."
}

# Function to debug API responses
debug_response() {
  local response="$1"
  if $DEBUG_MODE; then
    echo "API Response:" >&2
    echo "$response" | jq . >&2 || echo "$response" >&2
  fi
}

# Function to find the next available VM ID
get_available_vm_id() {
  local max_attempts=100
  local attempts=0
  local current_id=$VM_ID_START

  while (( attempts < max_attempts )); do
    local response=$(curl -s -k -X GET "$PROXMOX_API_URL/cluster/nextid?vmid=$current_id" \
      -H "CSRFPreventionToken: $CSRF_TOKEN" \
      -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE")

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
  mkdir -p "$TEMP_ISO_DIR"
  mkdir -p "$TEMP_FS_DIR/openstack/2015-10-15"

  cp "$USER_DATA_FILE" "$TEMP_FS_DIR/openstack/2015-10-15/user_data"

  local iso_filename="CI_${VM_ID}_${VM_NAME}.iso"
  mkisofs -r -J -jcharset utf-8 -V config-2 -o "$TEMP_ISO_DIR/$iso_filename" "$TEMP_FS_DIR" > /dev/null 2>&1

  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to create Cloud-Init ISO."
    rm -rf "$TEMP_FS_DIR" "$TEMP_ISO_DIR"
    exit 1
  fi

  rm -rf "$TEMP_FS_DIR"
  echo "Cloud-Init ISO created at $TEMP_ISO_DIR/$iso_filename."
}

# Function to upload the ISO
upload_iso() {
  local iso_filename="CI_${VM_ID}_${VM_NAME}.iso"
  echo "Uploading Cloud-Init ISO ($iso_filename) to Proxmox storage ($STORAGE_NAME)..."
  local response=$(curl -s -k -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/storage/$STORAGE_NAME/upload" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE" \
    -F "content=iso" \
    -F "filename=@$TEMP_ISO_DIR/$iso_filename")

  debug_response "$response"

  local error=$(echo "$response" | jq -r '.errors // empty')
  if [[ $? -ne 0 || -n "$error" ]]; then
    echo "Error: Failed to upload Cloud-Init ISO. Error details:"
    echo "$error"
    exit 1
  fi

  rm -rf "$TEMP_ISO_DIR"
  echo "Cloud-Init ISO uploaded and temporary ISO folder cleaned up successfully."
}

# Function to clone a VM from the template
clone_vm() {
  echo "Cloning template VM ($TEMPLATE_VM_ID) to create VM ($VM_ID)..."
  local response=$(curl -s -k -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$TEMPLATE_VM_ID/clone" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE" \
    --data-urlencode "newid=$VM_ID" \
    --data-urlencode "name=$VM_NAME")

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
  local response=$(curl -s -k -X PUT "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/resize" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE" \
    --data-urlencode "disk=scsi0" \
    --data-urlencode "size=$DISK_RESIZE")

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

  echo "Disk resized successfully to $DISK_RESIZE."
}

# Function to attach the ISO to the VM
attach_iso() {
  echo "Attaching Cloud-Init ISO to VM $VM_ID..."
  local iso_filename="CI_${VM_ID}_${VM_NAME}.iso"
  local response=$(curl -s -k -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/config" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE" \
    --data-urlencode "ide2=$STORAGE_NAME:iso/$iso_filename,media=cdrom")

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
  parse_arguments "$@"
  validate_arguments
  authenticate
  get_available_vm_id
  create_cloudinit_iso
  upload_iso
  clone_vm
  resize_disk
  attach_iso
  echo "VM creation and configuration completed successfully!"
}

# Run the main function
main "$@"
