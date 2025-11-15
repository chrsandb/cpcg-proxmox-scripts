#!/bin/bash

# Default Variables
PVE_HOST="10.17.1.12"
PVE_USER="root@pam"
PVE_PASSWORD=""
NODE_NAME="pve02"
STORAGE_NAME="vm_data"
TEMPLATE_ID=9500
TEMPLATE_NAME="cp-mngt-template"
CORES=8
MEMORY=16384
BRIDGE="vmbr0"
IMAGE_PATH="/mnt/pve/media/template/qcow/"
QCOW2_IMAGE="jaguar_opt_main-777-991001696.qcow2"
COPY_IMAGE=false
PROXMOX_PORT="8006"
PROXMOX_API_URL=""
DEBUG_MODE=false

CSRF_TOKEN=""
PVE_AUTH_COOKIE=""

# Function to print the help text
print_help() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --host <Proxmox Host>          Proxmox server IP or hostname (default: 10.17.1.21)"
  echo "  --user <Username>              Proxmox API username (default: root@pam)"
  echo "  --password <Password>          Proxmox API password (required)"
  echo "  --node <Node Name>             Proxmox node name (default: pve)"
  echo "  --storage <Storage Name>       Proxmox storage name (default: vm_data)"
  echo "  --template-id <Template ID>    VM ID for the template (default: 9500)"
  echo "  --template-name <Template Name> VM name for the template (default: cp-mngt-template)"
  echo "  --cores <Cores>                Number of CPU cores (default: 8)"
  echo "  --memory <Memory>              Memory size in MB (default: 16384)"
  echo "  --bridge <Bridge>              Network bridge (default: vmbr0)"
  echo "  --qcow2_image <QCOW2 File>     QCOW2 file path (default: jaguar_opt_main-777-991001696.qcow2)"
  echo "  --copy-image                   Copy the QCOW2 file to the Proxmox server"
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
      --template-id) TEMPLATE_ID="$2"; shift; shift ;;
      --template-name) TEMPLATE_NAME="$2"; shift; shift ;;
      --cores) CORES="$2"; shift; shift ;;
      --memory) MEMORY="$2"; shift; shift ;;
      --bridge) BRIDGE="$2"; shift; shift ;;
      --qcow2_image) QCOW2_IMAGE="$2"; shift; shift ;;
      --copy-image) COPY_IMAGE=true; shift ;;
      --debug) DEBUG_MODE=true; shift ;;
      -h|--help) print_help; exit 0 ;;
      *) echo "Unknown option: $1"; print_help; exit 1 ;;
    esac
  done
}

# Validate required arguments
validate_arguments() {
  if [[ -z "$QCOW2_IMAGE" || (! -f "$QCOW2_IMAGE" && "$COPY_IMAGE" == true) ]]; then
    echo "Error: --qcow2_image argument is required and must point to a valid QCOW2 file."
    print_help
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

  debug_response "$response"

  CSRF_TOKEN=$(echo "$response" | jq -r '.data.CSRFPreventionToken')
  PVE_AUTH_COOKIE=$(echo "$response" | jq -r '.data.ticket')

  if [[ -z "$CSRF_TOKEN" || -z "$PVE_AUTH_COOKIE" ]]; then
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

# Function to SCP the QCOW2 file
scp_qcow2_image() {
  if $COPY_IMAGE; then
    echo "Transferring QCOW2 image to Proxmox server..."
    scp "$QCOW2_IMAGE" "$PVE_USER@$PVE_HOST:$IMAGE_PATH"
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
  echo "Creating VM $TEMPLATE_ID for the template..."
  local response=$(curl -s -k -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE" \
    --data-urlencode "vmid=$TEMPLATE_ID" \
    --data-urlencode "name=$TEMPLATE_NAME" \
    --data-urlencode "cores=$CORES" \
    --data-urlencode "memory=$MEMORY" \
    --data-urlencode "net0=virtio,bridge=$BRIDGE" \
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
  echo "Waiting for scsi0 disk to be available for VM $TEMPLATE_ID..."
  local timeout=120  # Timeout in seconds
  local interval=5   # Interval between checks
  local elapsed=0

  while (( elapsed < timeout )); do
    local response=$(curl -s -k -X GET "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$TEMPLATE_ID/config" \
      -H "CSRFPreventionToken: $CSRF_TOKEN" \
      -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE")

    debug_response "$response"

    local scsi0=$(echo "$response" | jq -r '.data.scsi0 // empty')
    if [[ -n "$scsi0" ]]; then
      echo "scsi0 disk is available for VM $TEMPLATE_ID."
      return 0
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  echo "Error: Timeout waiting for scsi0 disk to be available for VM $TEMPLATE_ID."
  exit 1
}

# Function to import the QCOW2 image
import_qcow2_image() {
  echo "Importing QCOW2 image into the VM..."
  local response=$(curl -s -k -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$TEMPLATE_ID/config" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE" \
    --data-urlencode "scsi0=$STORAGE_NAME:0,import-from=$IMAGE_PATH$(basename "$QCOW2_IMAGE")")

  debug_response "$response"

  local error=$(echo "$response" | jq -r '.errors // empty')
  if [[ $? -ne 0 || -n "$error" ]]; then
    echo "Error: Failed to import QCOW2 image. Error details:"
    echo "$error"
    exit 1
  fi

  wait_for_scsi0_disk  # Ensure scsi0 disk is ready before proceeding

  echo "QCOW2 image imported successfully."
}

# Function to configure the VM for templating
configure_vm() {
  echo "Configuring VM $TEMPLATE_ID for template creation..."
  local response=$(curl -s -k -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$TEMPLATE_ID/config" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE" \
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
  echo "Converting VM $TEMPLATE_ID to a template..."
  local response=$(curl -s -k -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$TEMPLATE_ID/template" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE")

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
  parse_arguments "$@"
  validate_arguments
  authenticate
  scp_qcow2_image
  create_vm
  import_qcow2_image
  configure_vm
  convert_to_template
  echo "Template creation completed successfully!"
}

# Run the main function
main "$@"
