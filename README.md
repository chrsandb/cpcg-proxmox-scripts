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

### Template Creation Scripts

#### Gateway Template
```bash
./create_cpgw_template.sh --password "your-password" [OPTIONS]
```

#### Management Template
```bash
./create_cpmngt_template.sh --password "your-password" [OPTIONS]
```

**Common Options**:
- `--host <IP>`: Proxmox server IP (default: 10.17.1.12)
- `--user <username>`: API username (default: root@pam)
- `--password <password>`: API password (required)
- `--node <node>`: Proxmox node name (default: pve02)
- `--storage <storage>`: Storage name (default: vm_data)
- `--template-id <id>`: VM ID for template (default: 9600/9500)
- `--template-name <name>`: Template name
- `--cores <count>`: CPU cores (default: 8)
- `--memory <MB>`: Memory in MB (default: 8192/16384)
- `--qcow2_image <path>`: Path to QCOW2 image
- `--copy-image`: Transfer image to Proxmox server
- `--debug`: Enable debug output

### VM Creation from Template

```bash
./create_cpvm_with_cloudinit_iso_from_template.sh --password "your-password" [OPTIONS]
```

**Options**:
- `--host <IP>`: Proxmox server IP (default: 10.17.1.12)
- `--user <username>`: API username (default: root@pam)
- `--password <password>`: API password (required)
- `--node <node>`: Proxmox node name (default: pve02)
- `--storage <storage>`: Storage name (default: vm_data)
- `--template-id <id>`: Source template ID (required)
- `--vm-id <id>`: New VM ID (required)
- `--vm-name <name>`: VM name (required)
- `--cores <count>`: CPU cores (default: 4)
- `--memory <MB>`: Memory in MB (default: 4096)
- `--disk-size <GB>`: Disk size in GB (default: 32)
- `--hostname <name>`: VM hostname
- `--ip-address <IP>`: IP address for eth0
- `--gateway <IP>`: Default gateway
- `--dns <IP>`: DNS server
- `--ssh-key <key>`: SSH public key
- `--user-data <file>`: Path to user-data file
- `--debug`: Enable debug output

### VM Deletion

```bash
./delete_cpvm_and_cloudinit_iso.sh --password "your-password" --vm-id <id> [OPTIONS]
```

**Options**:
- `--host <IP>`: Proxmox server IP (default: 10.17.1.12)
- `--user <username>`: API username (default: root@pam)
- `--password <password>`: API password (required)
- `--node <node>`: Proxmox node name (default: pve02)
- `--vm-id <id>`: VM ID to delete (required)
- `--debug`: Enable debug output

## Examples

### Create Gateway Template
```bash
./create_cpgw_template.sh \
  --password "secure-password" \
  --host "10.17.1.12" \
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
  --host "10.17.1.12" \
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
  --template-id 9600 \
  --vm-id 100 \
  --vm-name "gateway-01" \
  --hostname "gateway-01.example.com" \
  --ip-address "192.168.1.100/24" \
  --gateway "192.168.1.1" \
  --dns "8.8.8.8" \
  --ssh-key "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ..."
```

### Delete VM
```bash
./delete_cpvm_and_cloudinit_iso.sh \
  --password "secure-password" \
  --vm-id 100
```

## Configuration

### Environment Variables

You can set default values using environment variables:

```bash
export PVE_HOST="10.17.1.12"
export PVE_USER="root@pam"
export PVE_PASSWORD="your-password"
export NODE_NAME="pve02"
export STORAGE_NAME="vm_data"
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