# CPCG Proxmox Scripts

A collection of Bash scripts for managing Proxmox Virtual Environment (PVE) virtual machines, focusing on template creation, VM deployment with Cloud-Init, and cleanup operations.

## Overview

This repository contains scripts for automating Proxmox VM management tasks:

- **Template Creation**: Create VM templates from QCOW2 images for gateway and management systems
- **VM Deployment**: Deploy VMs from templates with Cloud-Init configuration
- **Cleanup Operations**: Remove VMs and associated Cloud-Init ISOs

## Prerequisites

- Proxmox Virtual Environment (PVE) server
- `curl` and `jq` installed on the system running the scripts
- `scp` for file transfers (when using `--copy-image` option)
- Access to Proxmox API with appropriate permissions

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/chrsandb/cpcg-proxmox-scripts.git
   cd cpcg-proxmox-scripts
   ```

2. Make scripts executable:
   ```bash
   chmod +x *.sh
   ```

3. Install required dependencies:
   ```bash
   # On macOS
   brew install jq curl openssh
   
   # On Ubuntu/Debian
   sudo apt-get install jq curl openssh-client
   
   # On RHEL/CentOS
   sudo yum install jq curl openssh-clients
   ```

4. Configure your environment (optional):
   ```bash
   cp .env.template .env
   # Edit .env with your Proxmox details
   ```

## Quick Start Guide

### First-Time Setup

1. **Verify Proxmox Access**:
   ```bash
   # Test API connectivity (replace with your details)
   curl -k https://192.168.1.12:8006/api2/json/version
   ```

2. **Prepare QCOW2 Image**:
   - Place your QCOW2 image on the Proxmox host or local machine
   - Note the full path to the image file

3. **Create Your First Template**:
   ```bash
   # For a management template (single NIC)
   ./create_cpmngt_template.sh \
     --host "192.168.1.12" \
     --user "root@pam" \
     --template-id 9600 \
     --template-name "cp-mgmt-template" \
     --qcow2_image "/var/lib/vz/template/iso/management.qcow2"
   
   # You'll be prompted for password securely
   ```

4. **Deploy VM from Template**:
   ```bash
   # Create a Cloud-Init user-data YAML file first
   # See cp-mngt-user_data-example.yaml for reference
   
   ./create_cpvm_with_cloudinit_iso_from_template.sh \
     --host "192.168.1.12" \
     --template 9600 \
     --name "my-first-vm" \
     --user-data "cp-mngt-user_data-example.yaml"
   ```

5. **Verify and Start Your VM**:
   - Log into Proxmox web UI
   - Locate your new VM (ID will be shown in output)
   - Start the VM and access via console or SSH

### Typical Workflow

```bash
# Step 1: Create template (one-time setup)
./create_cpgw_template.sh --host 192.168.1.12 --template-id 9610 ...

# Step 2: Deploy multiple VMs from template
./create_cpvm_with_cloudinit_iso_from_template.sh --template 9610 --name "gw-01" ...
./create_cpvm_with_cloudinit_iso_from_template.sh --template 9610 --name "gw-02" ...

# Step 3: Clean up when done
./delete_cpvm_and_cloudinit_iso.sh --vm-id 100
```

## Scripts Overview

### 1. create_cpgw_template.sh

Creates a Proxmox VM template for gateway systems from a QCOW2 image.

**Purpose**: Automates the creation of gateway VM templates with multiple network interfaces.

**Key Features**:
- Creates VM with configurable number of network interfaces
- Imports QCOW2 images via Proxmox API
- Configures VM for template conversion
- Supports optional image transfer via SCP

### 2. create_cpmngt_template.sh

Creates a Proxmox VM template for management systems from a QCOW2 image.

**Purpose**: Automates the creation of management VM templates with single network interface.

**Key Features**:
- Creates VM with single network interface
- Imports QCOW2 images via Proxmox API
- Configures VM for template conversion
- Supports optional image transfer via SCP

### 3. create_cpvm_with_cloudinit_iso_from_template.sh

Creates virtual machines from existing templates with Cloud-Init ISO configuration.

**Purpose**: Deploys VMs from templates with automated initial configuration via Cloud-Init.

**Key Features**:
- Clones VMs from templates
- Generates Cloud-Init ISO with user data
- Configures network settings
- Supports multiple network interfaces
- Automatic ISO cleanup on VM deletion

### 4. delete_cpvm_and_cloudinit_iso.sh

Removes virtual machines and their associated Cloud-Init ISOs.

**Purpose**: Cleans up VMs and removes temporary Cloud-Init configuration files.

**Key Features**:
- Stops and deletes VMs
- Removes associated Cloud-Init ISOs
- Handles cleanup of temporary files

## Usage

All scripts load defaults from `.env` and allow CLI flags to override them.

### Template Creation Scripts

#### Gateway Template
```bash
./create_cpgw_template.sh [--password "your-password"] [OPTIONS]
```

#### Management Template
```bash
./create_cpmngt_template.sh [--password "your-password"] [OPTIONS]
```

**Common Options**:
- `--host <IP>`: Proxmox server IP (default: from `.env`)
- `--user <username>`: API username (default: from `.env`)
- `--password <password>`: API password (prompts if omitted; or set `PVE_PASSWORD`)
- `--node <node>`: Proxmox node name (default: from `.env`)
- `--storage <storage>`: Storage name (default: from `.env` `STORAGE_NAME_DISK`)
- `--template-id <id>`: VM ID for template (default: from `.env`)
- `--template-name <name>`: Template name (default: from `.env`)
- `--cores <count>`: CPU cores (default: from `.env`)
- `--memory <MB>`: Memory in MB (default: from `.env`)
- `--qcow2_image <path>`: Path to QCOW2 image (default: from `.env`)
- `--copy-image`: Transfer image to Proxmox server
- `--ca-cert <path>`: Path to CA certificate for TLS validation
- `--insecure`: Allow insecure TLS (self-signed). Not recommended.
- `--debug`: Enable debug output

### VM Creation from Template

```bash
./create_cpvm_with_cloudinit_iso_from_template.sh [--password "your-password"] [OPTIONS]
```

**Options**:
- `--host <IP>`: Proxmox server IP (default: from `.env`)
- `--user <username>`: API username (default: from `.env`)
- `--password <password>`: API password (prompts if omitted; or set `PVE_PASSWORD`)
- `--node <node>`: Proxmox node name (default: from `.env`)
- `--storage <storage>`: Storage name for ISO upload (default: from `.env` `STORAGE_NAME_ISO`)
- `--template <id>`: Source template ID (default: from `.env`)
- `--resize <value>`: Disk resize value (default: from `.env`)
- `--name <name>`: VM name (default: from `.env`)
- `--start-id <id>`: Start searching for VM IDs from this value (default: from `.env`)
- `--user-data <file>`: Path to Cloud-Init user-data YAML file (default: from `.env`). See example files: `cp-gw1-single-user_data-example.yaml` and `cp-mngt-user_data-example.yaml`
- `--ca-cert <path>`: Path to CA certificate for TLS validation
- `--insecure`: Allow insecure TLS (self-signed). Not recommended.
- `--debug`: Enable debug output

### VM Deletion

```bash
./delete_cpvm_and_cloudinit_iso.sh [--password "your-password"] --vm-id <id> [OPTIONS]
```

**Options**:
- `--host <IP>`: Proxmox server IP (default: from `.env`)
- `--user <username>`: API username (default: from `.env`)
- `--password <password>`: API password (prompts if omitted; or set `PVE_PASSWORD`)
- `--node <node>`: Proxmox node name (default: from `.env`)
- `--storage <storage>`: Storage name for ISO upload (default: from `.env` `STORAGE_NAME_ISO`)
- `--vm-id <id>`: VM ID to delete (required)
- `--ca-cert <path>`: Path to CA certificate for TLS validation
- `--insecure`: Allow insecure TLS (self-signed). Not recommended.
- `--debug`: Enable debug output

## Examples

### Complete Workflow Examples

#### Example 1: Gateway VM Deployment (Full Workflow)

```bash
# Step 1: Create gateway template with 4 NICs
./create_cpgw_template.sh \
  --host "192.168.1.12" \
  --user "root@pam" \
  --node "pve" \
  --template-id 9610 \
  --template-name "cp-gw-r81.20" \
  --qcow2_image "/var/lib/vz/template/iso/cp-gw-r81.20.qcow2" \
  --cores 8 \
  --memory 8192 \
  --nics 4 \
  --bridge-base "vmbr" \
  --ca-cert "/path/to/ca-cert.pem"

# Step 2: Deploy gateway VM with custom configuration
./create_cpvm_with_cloudinit_iso_from_template.sh \
  --host "192.168.1.12" \
  --template 9610 \
  --name "cp-gateway-01" \
  --resize "+80G" \
  --start-id 100 \
  --user-data "cp-gw1-single-user_data-example.yaml" \
  --ca-cert "/path/to/ca-cert.pem"

# Step 3: Deploy second gateway with same template
./create_cpvm_with_cloudinit_iso_from_template.sh \
  --template 9610 \
  --name "cp-gateway-02" \
  --resize "+80G" \
  --user-data "cp-gw2-user_data.yaml"
```

#### Example 2: Management VM with Custom Network

```bash
# Create management template
./create_cpmngt_template.sh \
  --host "192.168.1.12" \
  --template-id 9600 \
  --template-name "cp-mgmt-r81.20" \
  --qcow2_image "/var/lib/vz/template/iso/cp-mgmt-r81.20.qcow2" \
  --cores 8 \
  --memory 16384 \
  --bridge "vmbr0"

# Deploy management VM
./create_cpvm_with_cloudinit_iso_from_template.sh \
  --template 9600 \
  --name "cp-management" \
  --resize "+200G" \
  --user-data "cp-mngt-user_data-example.yaml"
```

#### Example 3: Using Environment Variables

```bash
# Set environment variables
export PVE_HOST="192.168.1.12"
export PVE_USER="root@pam"
export PVE_PASSWORD="your-secure-password"
export NODE_NAME="pve"
export STORAGE_NAME_ISO="local"

# Now run scripts without repeating parameters
./create_cpgw_template.sh \
  --template-id 9610 \
  --template-name "gateway-template" \
  --qcow2_image "/path/to/image.qcow2"
```

#### Example 4: Development with Self-Signed Certificates

```bash
# For development/testing environments only
./create_cpgw_template.sh \
  --host "192.168.1.12" \
  --template-id 9610 \
  --insecure \
  --debug \
  --template-name "dev-gateway"
  # ... other options
```

### Skip Bridge Indexes (Gateway Template Only)

The `create_cpgw_template.sh` script supports selective bridge configuration when creating gateway templates. Use the `--skip-bridge-indexes` option to exclude specific bridge indexes from the network configuration.

**Syntax**: Comma-separated list of zero-indexed bridge numbers to skip  
**Example**: `--skip-bridge-indexes "1,3"` skips bridges 1 and 3

**Usage Example**:
```bash
./create_cpgw_template.sh \
  --password "secure-password" \
  --host "192.168.1.12" \
  --template-name "cp-gateway-template" \
  --qcow2_image "/path/to/gateway.qcow2" \
  --copy-image \
  --cores 8 \
  --memory 8192 \
  --nics 4 \
  --skip-bridge-indexes "1,3"
```

This example creates a 4-NIC gateway template but only configures bridges 0 and 2 (skipping 1 and 3).

### Additional Use Cases

#### Delete VM and Clean Up
```bash
# Delete specific VM and its Cloud-Init ISO
./delete_cpvm_and_cloudinit_iso.sh \
  --host "192.168.1.12" \
  --vm-id 100

# With debug output
./delete_cpvm_and_cloudinit_iso.sh \
  --vm-id 101 \
  --debug
```

#### Using .env Configuration File
```bash
# Create .env file with common settings
cat > .env << 'EOF'
PVE_HOST="192.168.1.12"
PVE_USER="root@pam"
NODE_NAME="pve"
STORAGE_NAME_DISK="local-lvm"
STORAGE_NAME_ISO="local"
EOF

# Scripts will automatically use .env values
./create_cpgw_template.sh --template-id 9610 --template-name "my-gateway"
```

## Configuration

### .env Configuration

Copy `.env.template` to `.env` and fill in values:

```bash
cp .env.template .env
```

### Authentication

You can authenticate with either username/password (default) or an API token.

- Password auth: set `PVE_AUTH_MODE="password"` and `PVE_PASSWORD`.
- Token auth: set `PVE_AUTH_MODE="token"` plus `PVE_TOKEN_ID` and `PVE_TOKEN_SECRET`.
- If `PVE_AUTH_MODE` is empty, token auth is used when both token values are present; otherwise password auth is used.

If `PVE_PASSWORD` is not provided, the scripts will securely prompt for it at runtime to avoid exposing credentials in process arguments.

### Logging & Error Handling

- All scripts emit timestamped log lines to stderr; success messages are logged at `INFO` level.
- `--debug` preserves structured API responses while redacting secrets.
- Traps are registered for `ERR`/`EXIT` to surface unexpected errors early and allow future cleanup hooks.

### Input Validation

- Hosts are validated as IPv4 addresses.
- VM IDs, cores, memory, NIC counts, and start IDs must be positive integers.
- Disk resize values must match `+<number>[G|M]` (e.g., `+10G`).
- File paths (e.g., `--user-data` YAML files, QCOW2 images) must exist and be readable when required.

### Reliability / Retries

- All Proxmox API calls run through a retry wrapper with exponential backoff.
- Defaults: `CURL_MAX_RETRIES=3`, `CURL_BACKOFF_INITIAL=2s`, `CURL_BACKOFF_MAX=30s` (override via env vars).

`PVE_TOKEN_ID` can be either the token name (e.g., `mytoken`) or the full token ID (e.g., `root@pam!mytoken`).
API token authentication has not been tested in this repository yet.

Suggested Proxmox defaults if you are using a single-node install:
- `NODE_NAME="pve"` (the node name shown in the Proxmox UI)
- `STORAGE_NAME_ISO="local"` for ISO uploads
- `STORAGE_NAME_DISK="local-lvm"` for VM disks

### Template ID Relationships

These IDs are related but serve different roles:

- `CPMNGT_TEMPLATE_ID` and `CPGW_TEMPLATE_ID` are the template VM IDs created by `create_cpmngt_template.sh` and `create_cpgw_template.sh`.
- `CPVM_TEMPLATE_VM_ID` is the source template ID that `create_cpvm_with_cloudinit_iso_from_template.sh` clones from.

If you want to deploy VMs from the template you just created, set `CPVM_TEMPLATE_VM_ID` to match either `CPMNGT_TEMPLATE_ID` or `CPGW_TEMPLATE_ID`.

### Environment Variables

Defaults are loaded from `.env`:

```bash
PVE_HOST="192.168.1.12"
PVE_USER="root@pam"
PVE_PASSWORD="your-password"
PVE_AUTH_MODE="password"
PVE_TOKEN_ID="mytoken"
PVE_TOKEN_SECRET="your-token-secret"
NODE_NAME="pve"
STORAGE_NAME_DISK="local-lvm"
STORAGE_NAME_ISO="local"
```

### Cloud-Init Configuration

For VM deployment, Cloud-Init configuration is provided via YAML files following the [Cloud-Init documentation format](https://cloudinit.readthedocs.io/).

**User-Data File (YAML format)**:
- Defines initial VM configuration including users, SSH keys, hostname, and startup commands
- Must start with `#cloud-config` header
- **Example files provided**:
  - `cp-gw1-single-user_data-example.yaml` - Gateway VM configuration example
  - `cp-mngt-user_data-example.yaml` - Management VM configuration example

**Common Cloud-Init Components**:
- **user-data**: User accounts, SSH keys, hostname, packages, and run commands (YAML format)
- **network-config**: Network interface settings (optional, not used by these scripts)
- **meta-data**: Instance metadata (optional, not used by these scripts)

## Security Considerations

### Production Security Best Practices

1. **TLS/SSL Certificates**
   - Always use `--ca-cert` with valid CA certificate in production
   - Never use `--insecure` in production environments
   - Regularly update and rotate certificates

2. **Credential Management**
   - Use environment variables instead of CLI arguments:
     ```bash
     export PVE_PASSWORD="secure-password"
     ./script.sh  # Password not visible in process list
     ```
   - Store credentials in `.env` file with restricted permissions:
     ```bash
     chmod 600 .env
     ```
   - Use password prompts for interactive use (scripts prompt automatically)
   - Consider implementing API token auth for automation

3. **API Access Control**
   - Create dedicated Proxmox users with minimal required permissions
   - Use separate credentials for different environments
   - Regularly audit API access logs
   - Implement IP restrictions where possible

4. **Debug Output Safety**
   - Credentials are automatically redacted from `--debug` output
   - Avoid logging debug output to shared/public locations
   - Review debug logs before sharing for support

5. **File Permissions**
   - Protect configuration files: `chmod 600 .env`
   - Protect Cloud-Init user-data files (may contain passwords/keys)
   - Ensure QCOW2 images have appropriate permissions

6. **Network Security**
   - Use VPN or secure network when accessing Proxmox API
   - Limit API access to trusted networks
   - Monitor for unauthorized API access attempts

### Development vs Production

| Practice | Development | Production |
|----------|-------------|------------|
| TLS Validation | `--insecure` OK | `--ca-cert` required |
| Debug Mode | Recommended | Use sparingly |
| Password in .env | OK | Use prompts/env vars |
| Shared Credentials | OK | Never |
| Log Storage | Local | Secure/centralized |

## Troubleshooting

### Common Issues and Solutions

#### 1. Authentication Failed

**Symptoms**: `Authentication failed` or `401 Unauthorized` errors

**Solutions**:
- Verify username format is correct: `user@realm` (e.g., `root@pam`, `admin@pve`)
- Check password is correct (avoid special shell characters or use quotes)
- Verify user has API access permissions in Proxmox
- Test authentication manually:
  ```bash
  curl -k -d "username=root@pam&password=yourpass" \
    https://192.168.1.12:8006/api2/json/access/ticket
  ```
- Ensure Proxmox API is accessible from your machine:
  ```bash
  nc -zv 192.168.1.12 8006
  ```

#### 2. SSL/TLS Certificate Errors

**Symptoms**: `SSL certificate problem: self signed certificate`

**Solutions**:
- **For Production**: Use `--ca-cert /path/to/ca-cert.pem` with your CA certificate
- **For Development Only**: Use `--insecure` flag (not recommended for production)
- Export certificate from Proxmox and provide its path:
  ```bash
  # Download cert from Proxmox
  echo | openssl s_client -connect 192.168.1.12:8006 2>/dev/null | \
    openssl x509 > proxmox-ca.pem
  
  # Use it with scripts
  ./create_cpgw_template.sh --ca-cert proxmox-ca.pem ...
  ```

#### 3. QCOW2 Import Failed

**Symptoms**: `Error importing QCOW2 image` or task fails

**Solutions**:
- Verify QCOW2 file exists on Proxmox host:
  ```bash
  ssh root@192.168.1.12 "ls -lh /var/lib/vz/template/iso/yourfile.qcow2"
  ```
- Check file permissions (must be readable by Proxmox):
  ```bash
  ssh root@192.168.1.12 "chmod 644 /var/lib/vz/template/iso/yourfile.qcow2"
  ```
- Verify sufficient storage space:
  ```bash
  ssh root@192.168.1.12 "df -h /var/lib/vz"
  ```
- Check storage is mounted and accessible in Proxmox
- Ensure QCOW2 image is not corrupted:
  ```bash
  qemu-img check /path/to/image.qcow2
  ```
- If using `--copy-image`, verify SSH access and SCP works:
  ```bash
  scp /local/path/image.qcow2 root@192.168.1.12:/tmp/test.qcow2
  ```

#### 4. VM Creation Failed

**Symptoms**: `Error creating VM` or VM ID conflicts

**Solutions**:
- Verify VM ID is not already in use:
  ```bash
  # Via API
  curl -k https://192.168.1.12:8006/api2/json/nodes/pve/qemu/9610
  
  # Or in Proxmox UI: check VM list
  ```
- Ensure sufficient resources available:
  - Check CPU cores available
  - Verify memory is available (not overcommitted)
  - Confirm storage has space
- Check node name is correct:
  ```bash
  # List available nodes
  curl -k https://192.168.1.12:8006/api2/json/nodes
  ```
- Verify storage exists:
  ```bash
  # List storage
  curl -k https://192.168.1.12:8006/api2/json/nodes/pve/storage
  ```

#### 5. Network Configuration Issues

**Symptoms**: VM created but no network connectivity or bridge errors

**Solutions**:
- Verify bridge interfaces exist on Proxmox host:
  ```bash
  ssh root@192.168.1.12 "ip addr show | grep vmbr"
  ```
- Check bridge configuration in `/etc/network/interfaces`
- For gateway templates, ensure all required bridges (vmbr0-3) exist
- Use `--skip-bridge-indexes` to skip missing bridges:
  ```bash
  ./create_cpgw_template.sh --skip-bridge-indexes "2,3" ...
  ```
- Verify bridge is up and active:
  ```bash
  ssh root@192.168.1.12 "brctl show"
  ```

#### 6. Cloud-Init ISO Upload Failed

**Symptoms**: `Error uploading ISO` or ISO not found

**Solutions**:
- Verify ISO storage is configured in Proxmox
- Check storage type supports ISO content
- Ensure sufficient space on ISO storage:
  ```bash
  ssh root@192.168.1.12 "df -h /var/lib/vz/template/iso"
  ```
- Verify user-data YAML file is valid:
  ```yaml
  # Must start with this header
  #cloud-config
  hostname: myvm
  # ... rest of config
  ```
- Test Cloud-Init YAML syntax:
  ```bash
  # Install cloud-init tools
  cloud-init devel schema --config-file user_data.yaml
  ```

#### 7. Disk Resize Failed

**Symptoms**: `Failed to resize the disk` errors

**Solutions**:
- Verify resize format is correct: `+80G` or `+100M`
- Ensure disk format supports resizing (qcow2 or raw)
- Check user has permissions to resize disks
- Verify disk is not already at maximum size
- Use correct disk identifier (default is `scsi0`)
- Cannot shrink disks, only grow them

#### 8. VM Deletion Failed

**Symptoms**: VM not deleted or ISO cleanup fails

**Solutions**:
- Ensure VM is stopped before deletion
- Verify VM ID is correct
- Check for snapshots preventing deletion
- For ISO cleanup errors, verify storage is accessible
- Check file naming matches expected pattern: `CI_<VMID>_<VMNAME>.iso`
- Manual cleanup if needed:
  ```bash
  ssh root@192.168.1.12 "rm /var/lib/vz/template/iso/CI_100_vmname.iso"
  ```

#### 9. Performance Issues / Slow Operations

**Symptoms**: Scripts take very long to complete

**Solutions**:
- Check network latency to Proxmox:
  ```bash
  ping -c 5 192.168.1.12
  ```
- Verify Proxmox server is not overloaded:
  ```bash
  ssh root@192.168.1.12 "top -b -n 1 | head -20"
  ```
- Check storage I/O performance
- Reduce polling frequency if needed (edit scripts)
- For large images, use `--copy-image` for better progress tracking
- Enable `--debug` to see where time is spent

#### 10. Permission Denied Errors

**Symptoms**: Various permission errors during operations

**Solutions**:
- Verify Proxmox user has required permissions:
  - VM.Allocate (create VMs)
  - VM.Config.* (modify VM configuration)
  - Datastore.AllocateSpace (import images)
  - Sys.Modify (for some operations)
- Check storage permissions in Proxmox
- Ensure file permissions allow read/write
- For API token auth, verify token permissions match user

### Debug Mode

Enable detailed logging with `--debug` flag:

```bash
./script.sh --debug --password "password" [other-options]
```

Debug output includes:
- All API request URLs and methods
- API response data (with credentials redacted)
- Step-by-step progress information
- Timing information for operations
- Detailed error messages and context

Output is sent to STDERR for easier filtering:
```bash
# Capture debug output separately
./script.sh --debug 2> debug.log

# View only errors
./script.sh --debug 2>&1 | grep ERROR
```

### Getting Help

1. **Enable debug mode** and review output
2. **Check Proxmox logs** on the server:
   ```bash
   ssh root@192.168.1.12 "tail -f /var/log/pve/tasks/active"
   ```
3. **Review script help**: `./script.sh --help`
4. **Check GitHub Issues**: [Report bugs or ask questions](https://github.com/chrsandb/cpcg-proxmox-scripts/issues)
5. **Proxmox Documentation**: [Proxmox VE API](https://pve.proxmox.com/pve-docs/api-viewer/)

### Known Limitations

- Cannot resize disks smaller (only grow)
- Bridge configuration must exist before template creation
- Cloud-Init requires specific YAML format
- Some operations require VM to be stopped
- API token authentication not yet implemented (password only)
- Parallel execution not supported (run scripts sequentially)

## Frequently Asked Questions (FAQ)

### General Questions

**Q: Can I run multiple scripts simultaneously?**  
A: No, scripts should be run sequentially. Parallel execution may cause conflicts with VM IDs or resource allocation.

**Q: Do I need to install anything on the Proxmox server?**  
A: No, these scripts use the Proxmox REST API. You only need `curl`, `jq`, and optionally `scp` on the machine running the scripts.

**Q: Can I use these scripts with Proxmox clusters?**  
A: Yes, specify the appropriate node name with `--node`. Each script operates on a single node.

**Q: What Proxmox versions are supported?**  
A: These scripts are tested with Proxmox VE 7.x and 8.x. They should work with any version supporting the REST API v2.

### Template Questions

**Q: Can I create templates from existing VMs?**  
A: Not directly with these scripts. Use Proxmox UI or API to convert an existing VM to a template first.

**Q: How many NICs can a gateway template have?**  
A: Configurable via `--nics` parameter. Default is 4, but you can specify any number supported by your setup.

**Q: What if some bridge interfaces don't exist?**  
A: Use `--skip-bridge-indexes` to skip missing bridges. For example, `--skip-bridge-indexes "2,3"` skips vmbr2 and vmbr3.

**Q: Can I modify a template after creation?**  
A: Yes, but not with these scripts. Use Proxmox UI or API to modify template configuration.

### VM Deployment Questions

**Q: How are VM IDs assigned?**  
A: Scripts automatically find the next available VM ID starting from `--start-id` (default: 100).

**Q: Can I specify a specific VM ID?**  
A: Not directly. The scripts find the next available ID. If you need a specific ID, ensure it's available and adjust `--start-id`.

**Q: What happens if Cloud-Init ISO creation fails?**  
A: The script will stop and report an error. No VM will be created. Check your user-data YAML syntax.

**Q: Can I deploy multiple VMs from the same template?**  
A: Yes! That's the main purpose of templates. Just run the deployment script multiple times with different names.

**Q: How do I customize network settings?**  
A: Network configuration is handled via Cloud-Init user-data YAML file. See examples: `cp-gw1-single-user_data-example.yaml` and `cp-mngt-user_data-example.yaml`.

### Cloud-Init Questions

**Q: Where can I learn more about Cloud-Init?**  
A: See the [official Cloud-Init documentation](https://cloudinit.readthedocs.io/).

**Q: What's the difference between user-data, meta-data, and network-config?**  
A: 
- **user-data**: Main configuration (users, SSH keys, packages, commands)
- **meta-data**: Instance metadata (not used by these scripts)
- **network-config**: Network configuration (not used, configured in VM settings instead)

**Q: Can I use the same user-data file for multiple VMs?**  
A: Yes, but consider customizing hostname and other unique identifiers for each VM.

**Q: How do I validate my Cloud-Init YAML?**  
A: Use `cloud-init devel schema --config-file your-file.yaml` if you have cloud-init tools installed.

### Storage Questions

**Q: Can I use different storage for templates and ISOs?**  
A: Yes, specify different storage names with script parameters or in `.env` file.

**Q: What storage types are supported?**  
A: Any Proxmox-supported storage that allows VM disk images (for templates) and ISO storage (for Cloud-Init ISOs).

**Q: How much disk space do I need?**  
A: Depends on QCOW2 image size and disk resize value. Plan for: original image size + resize amount + overhead.

### Security Questions

**Q: Is it safe to use --insecure flag?**  
A: Only in development/testing environments. In production, always use `--ca-cert` for proper TLS validation.

**Q: Where should I store passwords?**  
A: Use environment variables or let the script prompt you. Never store passwords in version control or command history.

**Q: Can I use API tokens instead of passwords?**  
A: Not yet implemented. Currently, only username/password authentication is supported.

**Q: Are credentials logged?**  
A: No, credentials are automatically redacted from debug output.

### Troubleshooting Questions

**Q: Script hangs during execution, what should I do?**  
A: Enable `--debug` mode to see where it's stuck. Usually it's waiting for an API operation or task to complete.

**Q: How do I verify API connectivity?**  
A: Test with: `curl -k https://YOUR_HOST:8006/api2/json/version`

**Q: What if I get "Task failed" errors?**  
A: Check Proxmox task logs: `ssh root@pve 'tail -f /var/log/pve/tasks/active'`

**Q: Can I recover from a failed deployment?**  
A: Use the delete script to clean up partially created resources, then try again.

### Performance Questions

**Q: Why do operations take so long?**  
A: Large QCOW2 images take time to transfer and import. Network latency and storage I/O also affect performance.

**Q: Can I speed up image transfers?**  
A: If the image is already on the Proxmox host, don't use `--copy-image` flag.

**Q: Do scripts support progress bars?**  
A: Yes, scripts now show professional progress indicators with step tracking.

## Development

### Code Structure

The codebase is organized with shared functionality in `lib/common.sh`:

**Shared Library (`lib/common.sh`)**:
- Authentication and API helpers
- Input validation functions
- Logging with timestamps
- Error handling and retry logic
- Progress indicators
- Common VM operations

**Script Structure**:
Each script follows a consistent pattern:
1. Source shared library
2. Define script-specific configuration
3. Parse arguments with validation
4. Initialize authentication
5. Execute main workflow with progress tracking
6. Handle errors and cleanup via traps

### Testing

Test scripts in a development environment before production use:

1. **Enable debug mode** for detailed output:
   ```bash
   ./script.sh --debug --insecure ...
   ```

2. **Start with minimal resources**:
   ```bash
   # Test with small VM first
   ./create_cpmngt_template.sh --cores 2 --memory 2048 ...
   ```

3. **Verify operations work correctly**:
   - Check template creation in Proxmox UI
   - Test VM deployment
   - Verify cleanup operations work
   - Check ISO files are created/deleted properly

4. **Run shellcheck** for syntax validation:
   ```bash
   shellcheck -x *.sh lib/common.sh
   ```

5. **Test error handling**:
   ```bash
   # Test with invalid parameters
   ./script.sh --host "invalid-ip"
   ./script.sh --vm-id "not-a-number"
   ```

### Best Practices for Development

- Always test in dev environment first
- Use `--debug` flag during development
- Enable `--insecure` only for dev environments
- Check exit codes: `echo $?` after script execution
- Review Proxmox task logs for detailed operation info
- Test cleanup operations to avoid orphaned resources
- Validate Cloud-Init YAML before deployment

### Contributing

We welcome contributions! Here's how to get started:

1. **Fork the repository**
   ```bash
   git clone https://github.com/your-username/cpcg-proxmox-scripts.git
   cd cpcg-proxmox-scripts
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Follow existing code style
   - Add functions to `lib/common.sh` if reusable
   - Update documentation
   - Add examples if adding features

4. **Test thoroughly**
   - Run shellcheck on all modified files
   - Test in development environment
   - Verify all scripts still work
   - Check for regressions

5. **Commit with clear messages**
   ```bash
   git commit -m "feat: add new feature description"
   git commit -m "fix: resolve specific issue"
   git commit -m "docs: update documentation"
   ```

6. **Submit a pull request**
   - Describe changes clearly
   - Reference any related issues
   - Include testing details

### Coding Standards

- Use `bash` (not `sh` or other shells)
- Follow existing naming conventions
- Add comments for complex logic
- Use `local` for function variables
- Implement error handling for all operations
- Use `readonly` for constants
- Validate all user inputs
- Prefer `[[ ]]` over `[ ]` for conditionals
- Use `$()` instead of backticks for command substitution

### Running Tests

```bash
# Syntax validation
shellcheck -x *.sh lib/common.sh

# Manual testing workflow
./test_progress.sh  # Test progress indicators

# Full integration test (requires Proxmox access)
export PVE_HOST="your-test-proxmox"
./create_cpmngt_template.sh --template-id 9999 --insecure --debug ...
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for planned features and improvements including:
- Performance optimizations
- Enhanced security features
- Configuration file support
- Additional VM lifecycle operations
