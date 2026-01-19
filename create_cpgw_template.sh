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
CPGW_SKIP_BRIDGE_INDEXES=""

# Function to print the help text
print_help() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --host <Proxmox Host>          Proxmox server IP or hostname (default: 192.168.1.12)"
  echo "  --user <Username>              Proxmox API username (default: root@pam)"
  echo "  --password <Password>          Proxmox API password (prompts if omitted; or set PVE_PASSWORD)"
  echo "  --node <Node Name>             Proxmox node name (default: pve02)"
  echo "  --storage <Storage Name>       Proxmox storage name (default: from .env STORAGE_NAME_DISK)"
  echo "  --template-id <Template ID>    VM ID for the template (default: from .env CPGW_TEMPLATE_ID)"
  echo "  --template-name <Template Name> VM name for the template (default: from .env CPGW_TEMPLATE_NAME)"
  echo "  --cores <Cores>                Number of CPU cores (default: from .env CPGW_CORES)"
  echo "  --memory <Memory>              Memory size in MB (default: from .env CPGW_MEMORY)"
  echo "  --nics <Number of NICs>        Number of network interfaces (default: from .env CPGW_NICS)"
  echo "  --skip-bridge-indexes <Indexes> Comma-separated bridge indexes to skip (e.g., '1,3')"
  echo "  --qcow2_image <QCOW2 File>     QCOW2 file path (default: from .env CPGW_QCOW2_IMAGE)"
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
      --template-id) CPGW_TEMPLATE_ID="$2"; shift; shift ;;
      --template-name) CPGW_TEMPLATE_NAME="$2"; shift; shift ;;
      --cores) CPGW_CORES="$2"; shift; shift ;;
      --memory) CPGW_MEMORY="$2"; shift; shift ;;
      --nics) CPGW_NICS="$2"; shift; shift ;;
      --skip-bridge-indexes) CPGW_SKIP_BRIDGE_INDEXES="$2"; shift; shift ;;
      --qcow2_image) CPGW_QCOW2_IMAGE="$2"; shift; shift ;;
      --copy-image) CPGW_COPY_IMAGE=true; shift ;;
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
  if [[ -z "$CPGW_QCOW2_IMAGE" || (! -f "$CPGW_QCOW2_IMAGE" && "$CPGW_COPY_IMAGE" == true) ]]; then
    bail "$EXIT_USER" "--qcow2_image is required and must point to a valid QCOW2 file when copying."
  fi

  if [[ -z "$PVE_HOST" || -z "$PVE_USER" || -z "$NODE_NAME" || -z "$STORAGE_NAME_DISK" ]]; then
    bail "$EXIT_USER" "Missing one or more required arguments (--host, --user, --node, --storage)."
  fi

  validate_ipv4_or_bail "$PVE_HOST" "--host"
  validate_numeric_or_bail "$CPGW_TEMPLATE_ID" "--template-id"
  validate_numeric_or_bail "$CPGW_CORES" "--cores"
  validate_numeric_or_bail "$CPGW_MEMORY" "--memory"
  validate_numeric_or_bail "$CPGW_NICS" "--nics"

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

should_skip_bridge_index() {
  local index="$1"
  local skip_list="$CPGW_SKIP_BRIDGE_INDEXES"

  if [[ -z "$skip_list" ]]; then
    return 1  # Don't skip
  fi

  # Check if index is in the skip list (comma-separated)
  if [[ ",${skip_list}," == *",${index},"* ]]; then
    return 0  # Skip this index
  fi

  return 1  # Don't skip
}

# Function to SCP the QCOW2 file
scp_qcow2_image() {
  if $CPGW_COPY_IMAGE; then
    scp_file "$CPGW_QCOW2_IMAGE" "$PVE_USER@$PVE_HOST:$CPGW_IMAGE_PATH" "QCOW2 image to Proxmox server"
  else
    log_info "Skipping QCOW2 file transfer as --copy-image was not specified."
  fi
}

create_vm() {
  echo "Creating VM $CPGW_TEMPLATE_ID for the template..."

  # Build network interface configurations dynamically
  local net_configs=()
  local net_index=0
  for ((i = 0; i < CPGW_NICS; i++)); do
    if should_skip_bridge_index "$i"; then
      log_debug "Skipping bridge index $i"
      continue
    fi
    net_configs+=("--data-urlencode net${net_index}=virtio,bridge=${CPGW_BRIDGE_BASE}$i")
    net_index=$((net_index + 1))
  done

  # Join network configurations into a single string for the curl command
  local net_configs_str=$(IFS=" "; echo "${net_configs[*]}")

  # API call to create the VM
  local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu" \
    "${AUTH_HEADER_ARGS[@]}" \
    --data-urlencode "vmid=$CPGW_TEMPLATE_ID" \
    --data-urlencode "name=$CPGW_TEMPLATE_NAME" \
    --data-urlencode "cores=$CPGW_CORES" \
    --data-urlencode "memory=$CPGW_MEMORY" \
    --data-urlencode "scsihw=virtio-scsi-pci" \
    "$net_configs_str")

  debug_response "$response"

  check_api_error "$response" "create VM"

  echo "VM created successfully."
  if [[ -n "$CPGW_SKIP_BRIDGE_INDEXES" ]]; then
    echo "  (Skipped bridge indexes: $CPGW_SKIP_BRIDGE_INDEXES)"
  fi
}

# Function to import the QCOW2 image
import_qcow2_image() {
  echo "Importing QCOW2 image into the VM..."
  local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$CPGW_TEMPLATE_ID/config" \
    "${AUTH_HEADER_ARGS[@]}" \
    --data-urlencode "scsi0=$STORAGE_NAME_DISK:0,import-from=$CPGW_IMAGE_PATH$(basename "$CPGW_QCOW2_IMAGE")")

  debug_response "$response"

  local upid=$(get_jq_data "$response" '.data')
  check_api_error "$response" "import QCOW2 image"

  wait_for_task "$upid" "import_qcow2_image"
  wait_for_scsi0_disk  # Ensure scsi0 disk is ready before proceeding

  echo "QCOW2 image imported successfully."
}

# Function to configure the VM for templating
configure_vm() {
  echo "Configuring VM $CPGW_TEMPLATE_ID for template creation..."
  local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$CPGW_TEMPLATE_ID/config" \
    "${AUTH_HEADER_ARGS[@]}" \
    --data-urlencode "boot=order=scsi0" \
    --data-urlencode "serial0=socket" \
    --data-urlencode "vga=serial0" \
    --data-urlencode "agent=enabled=1,type=isa")

  debug_response "$response"

  check_api_error "$response" "configure the VM"
  echo "VM configured successfully."
}

# Function to convert the VM to a template
convert_to_template() {
  echo "Converting VM $CPGW_TEMPLATE_ID to a template..."
  local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$CPGW_TEMPLATE_ID/template" \
    "${AUTH_HEADER_ARGS[@]}")

  debug_response "$response"

  check_api_error "$response" "convert VM to a template"
  echo "VM converted to template successfully."
}

# Function to wait for scsi0 disk to exist
wait_for_scsi0_disk() {
  echo "Waiting for scsi0 disk to be available for VM $CPGW_TEMPLATE_ID..."
  local timeout=120  # Timeout in seconds
  local interval=5   # Interval between checks
  local elapsed=0

  while (( elapsed < timeout )); do
    local response=$(curl_with_retries -X GET "$PROXMOX_API_URL/nodes/$NODE_NAME/qemu/$CPGW_TEMPLATE_ID/config" \
      "${AUTH_HEADER_ARGS[@]}")

    debug_response "$response"

    local scsi0=$(get_jq_data "$response" '.data.scsi0')
    if [[ -n "$scsi0" ]]; then
      log_info "scsi0 disk is available for VM $CPGW_TEMPLATE_ID."
      return 0
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  bail "$EXIT_SYSTEM" "Timeout waiting for scsi0 disk to be available for VM $CPGW_TEMPLATE_ID."
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

main "$@"
