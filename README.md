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
- `--user-data <file>`: Path to Cloud-Init user-data file (default: from `.env`)
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

### Create Gateway Template
```bash
./create_cpgw_template.sh \
  --password "secure-password" \
  --host "192.168.1.12" \
  --template-name "cp-gateway-template" \
  --qcow2_image "/path/to/gateway.qcow2" \
  --copy-image \
  --cores 8 \
  --memory 8192 \
  --nics 4
```

### Create Management Template
```bash
./create_cpmngt_template.sh \
  --password "secure-password" \
  --host "192.168.1.12" \
  --template-name "cp-mgmt-template" \
  --qcow2_image "/path/to/management.qcow2" \
  --copy-image \
  --cores 8 \
  --memory 16384
```

### Deploy VM from Template
```bash
./create_cpvm_with_cloudinit_iso_from_template.sh \
  --password "secure-password" \
  --template 9600 \
  --name "gateway-01" \
  --start-id 100 \
  --user-data "/path/to/user_data"
```

### Delete VM
```bash
./delete_cpvm_and_cloudinit_iso.sh \
  --password "secure-password" \
  --vm-id 100
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

For VM deployment, you can provide custom Cloud-Init configuration:

- **user-data**: User and SSH key configuration
- **network-config**: Network interface settings
- **meta-data**: Instance metadata

## Security Considerations

- Store passwords securely (consider using password managers or environment variables)
- Use HTTPS for API communication (scripts use `-k` flag for self-signed certificates)
- Limit API user permissions to necessary operations
- Regularly rotate API credentials

## Troubleshooting

### Common Issues

1. **Authentication Failed**
   - Verify username format: `user@realm` (e.g., `root@pam`)
   - Check password and API permissions
   - Ensure Proxmox API is accessible

2. **QCOW2 Import Failed**
   - Verify QCOW2 file exists and is readable
   - Check storage permissions
   - Ensure sufficient storage space
   - Import tasks now fail fast; verify `CPMNGT_IMAGE_PATH` or `CPGW_IMAGE_PATH` points to a valid file on the Proxmox host

3. **VM Creation Failed**
   - Verify template exists
   - Check VM ID is not already in use
   - Ensure sufficient resources (CPU, memory, storage)

4. **Network Configuration Issues**
   - Verify bridge interfaces exist on Proxmox host
   - Check IP address format and subnet
   - Ensure gateway and DNS are reachable

### Debug Mode

Use `--debug` flag to enable detailed API response logging:

```bash
./script.sh --debug --password "password" [other-options]
```

Debug output is sent to STDERR and includes:
- API request/response details
- Authentication tokens (use with caution)
- Error messages and stack traces

## Development

### Code Structure

- Each script follows a modular structure with functions for:
  - Argument parsing and validation
  - Authentication
  - API operations
  - Error handling

### Testing

Test scripts in a development environment before production use:

1. Use `--debug` flag for detailed output
2. Test with minimal resources first
3. Verify cleanup operations work correctly

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for planned features and improvements including:
- Performance optimizations
- Enhanced security features
- Configuration file support
- Additional VM lifecycle operations
