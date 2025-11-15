#!/bin/bash

# Default Variables
PVE_HOST="10.17.1.6"
PVE_USER="root@pam"
PVE_PASSWORD=""
NODE_NAME="pve"
STORAGE_NAME="local"
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
  echo "  --host <Proxmox Host>          Proxmox server IP or hostname (default: 10.17.1.6)"
  echo "  --user <Username>              Proxmox API username (default: root@pam)"
  echo "  --password <Password>          Proxmox API password (required)"
  echo "  --node <Node Name>             Proxmox node name (default: pve)"
  echo "  --storage <Storage Name>       Proxmox storage name for ISO upload (default: local)"
  echo "  --vm-id <VM ID>                ID of the VM to delete (required)"
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
      --vm-id) VM_ID="$2"; shift; shift ;;
      --debug) DEBUG_MODE=true; shift ;;
      -h|--help) print_help; exit 0 ;;
      *) echo "Unknown option: $1"; print_help; exit 1 ;;
    esac
  done
}

# Validate required arguments
validate_arguments() {
  if [[ -z "$PVE_HOST" || -z "$PVE_USER" || -z "$PVE_PASSWORD" || -z "$NODE_NAME" || -z "$STORAGE_NAME" || -z "$VM_ID" ]]; then
    echo "Error: Missing one or more required arguments (--host, --user, --password, --node, --storage, --vm-id)."
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

# Function to check if the VM exists
check_vm_exists() {
  echo "Checking if VM $VM_ID exists..."
  local response=$(curl -s -k -X GET "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/status/current" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE")

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
  local response=$(curl -s -k -X GET "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/config" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE")

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
  local response=$(curl -s -k -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/status/stop" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE")

  debug_response "$response"

  local error=$(echo "$response" | jq -r '.errors // empty')
  if [[ $? -ne 0 || -n "$error" ]]; then
    echo "Error: Failed to stop the VM. Error details:"
    echo "$error"
    exit 1
  fi

  echo "Waiting for VM $VM_ID to stop..."
  while true; do
    local status_response=$(curl -s -k -X GET "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID/status/current" \
      -H "CSRFPreventionToken: $CSRF_TOKEN" \
      -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE")
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
  local response=$(curl -s -k -X DELETE "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$VM_ID" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE")

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
  echo "Deleting ISO $iso_filename from storage $STORAGE_NAME..."
  local response=$(curl -s -k -X DELETE "$PROXMOX_API_URL/nodes/$NODE_NAME/storage/$STORAGE_NAME/content/$STORAGE_NAME:iso/$iso_filename" \
    -H "CSRFPreventionToken: $CSRF_TOKEN" \
    -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE")

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
  parse_arguments "$@"
  validate_arguments
  authenticate
  check_vm_exists
  get_vm_name
  stop_vm
  delete_vm
  delete_iso
  echo "VM and associated ISO deleted successfully."
}

# Run the main function
main "$@"
