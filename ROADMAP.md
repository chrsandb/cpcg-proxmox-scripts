# ROADMAP.md

## Current State
This repository contains bash scripts for Proxmox VM management including:
- Template creation from QCOW2 images
- VM creation with Cloud-Init ISO from templates
- VM deletion with associated ISO cleanup

## Priority Levels

### 🔴 High Priority (Security & Stability)
Critical issues that should be addressed before production use.

### 🟡 Medium Priority (Quality & Efficiency)
Important improvements for maintainability and performance.

### 🟢 Low Priority (Features & UX)
Enhancements that add value but aren't blocking.

---

## Optimization Plan

### 1. Performance Optimizations 🟡
- Reduce redundant API calls (combine operations where possible)
- Implement exponential backoff for API retries (start 2s, max 30s)
- Optimize polling intervals for disk availability checks
- Parallelize independent operations where possible
- Add progress indicators to long-running operations
- Implement async operations for non-blocking tasks

### 2. Code Quality Improvements 🟡
- **Standardize error handling across all scripts**
  - Implement trap handlers for cleanup on EXIT and ERR signals
  - Standardize exit codes (0=success, 1=user error, 2=system error, 3=API error)
  - Add consistent error message format with actionable suggestions
- **Extract common functions to shared library**
  - Create `lib/common.sh` for shared functions (authenticate, debug_response, etc.)
  - Reduce code duplication between scripts
  - Centralize constants and default values
- **Add comprehensive input validation**
  - IP address validation with regex (IPv4/CIDR format)
  - VM ID validation (numeric, range checks)
  - Disk size validation (format: +XXG, valid units)
  - File path validation (existence, permissions, readable)
  - Network configuration validation (bridge names, valid interfaces)
- **Implement proper logging with timestamps**
  - Add log levels: DEBUG, INFO, WARN, ERROR
  - Log to both stdout and optional log file
  - Include timestamps in ISO 8601 format
- **Add better parameter validation including regex pattern matching**
  - Validate required vs optional parameters
  - Type checking for numeric parameters
  - Format validation for structured data

### 3. Security Enhancements 🔴
- **Fix critical SSL certificate bypass**
  - Remove `-k` flag from curl commands (currently bypasses certificate validation)
  - Add proper CA certificate validation
  - Document self-signed certificate handling for dev environments
  - Add `--insecure` flag with warning for dev use only
- **Secure credential handling**
  - **Immediate**: Remove password from process arguments (visible in `ps aux`)
  - Support password from environment variable (PVE_PASSWORD)
  - Support password from config file with restricted permissions (600)
  - Add password prompt with hidden input (using `read -s`)
  - Consider integration with system keychains/password managers
- **Sanitize debug output**
  - Remove sensitive data from debug logs (tokens, passwords, cookies)
  - Add `--debug-safe` mode that redacts credentials
  - Implement token masking in log output
- **Implement rate limiting for API calls**
  - Add configurable delays between API requests
  - Implement request throttling to prevent API overload
  - Add retry limits with backoff
- **Add audit logging**
  - Log all API operations with timestamps
  - Track who performed what operations
  - Optional syslog integration

### 4. Configuration Improvements 🟡
- **Add config file support**
  - Support `.proxmox.conf` in bash format (key=value)
  - Support YAML/JSON format for complex configurations
  - Support multiple profiles (dev, staging, prod)
  - Config file locations: `~/.proxmox.conf`, `./.proxmox.conf`, custom path
- **Implement default value handling**
  - Precedence order: CLI args > env vars > config file > defaults
  - Validate all configuration sources
  - Add `--show-config` flag to display effective configuration
- **Add environment variable support**
  - Support all parameters as environment variables
  - Standard naming: PVE_HOST, PVE_USER, NODE_NAME, etc.
  - Document environment variable usage in README
- **Add configuration validation**
  - Validate config file syntax before use
  - Check for required vs optional values
  - Provide helpful error messages for invalid configs

## Feature Enhancement Ideas

### 1. Template Management Features
- Template versioning system
- Template comparison capabilities
- Template backup functionality

### 2. Cloud-Init Enhancements
- Support for multiple cloud-init files
- Template-based user_data generation
- Automated cloud-init validation

### 3. VM Lifecycle Improvements
- VM state monitoring and alerts
- Automated VM snapshot creation
- Bulk operation support

### 4. Proxmox API Integration Enhancements
- Support for different Proxmox API versions
- Cluster-aware operations
- Advanced network configuration support

### 5. Testing and Debugging Features 🟡
- **Dry-run mode**
  - Add `--dry-run` flag to show what would be executed
  - Display API calls without executing them
  - Validate all parameters and show effective configuration
  - Useful for testing scripts before actual execution
- **Extended debug logging**
  - Add `--verbose` flag for detailed operation logging
  - Log all API requests and responses (sanitized)
  - Add timing information for performance analysis
  - Support log levels: TRACE, DEBUG, INFO, WARN, ERROR
- **Automated test suite**
  - Unit tests for individual functions
  - Integration tests with mock API responses
  - End-to-end tests in test environment
  - CI/CD pipeline integration
  - Test coverage reporting
- **Add validation mode**
  - Check prerequisites before execution
  - Verify Proxmox connectivity and authentication
  - Validate that storage, nodes, templates exist
  - Pre-flight checks for all operations

### 6. User Experience Improvements 🟢
- **Interactive mode**
  - Prompt for missing required parameters
  - Provide guided workflow with explanations
  - Support parameter validation with retry
  - Add confirmation prompts for destructive operations
- **Progress bars/status indicators**
  - Visual progress for long-running operations
  - ETA calculations for API operations
  - Real-time status updates
  - Spinners for operations without known duration
- **Better error messages with troubleshooting**
  - Actionable error messages with next steps
  - Common issues and solutions in error output
  - Link to documentation for complex errors
  - Suggest relevant command-line flags
- **Add command completion**
  - Bash/Zsh completion scripts
  - Tab completion for parameters
  - Contextual suggestions
- **Improved help documentation**
  - Add examples for common use cases
  - Include troubleshooting section
  - Add "Getting Started" quick guide
  - Generate man pages

### 7. Additional Script Functionality
- VM template creation from existing VMs
- VM cloning with configuration templates
- Automated VM customization
- Support for different storage types

### 8. Integration Capabilities 🟢
- Webhook support
- Configuration management integration (Ansible, Terraform)
- CI/CD pipeline support
- Monitoring and alerting integration
- API client library for other languages

---

## Implementation Roadmap

### Phase 1: Critical Security & Stability (Weeks 1-2) 🔴
**Goal**: Make scripts production-ready with secure operations

1. **Security Fixes**
   - Remove `-k` flag, add proper SSL validation
   - Implement secure credential handling (config file + env vars)
   - Sanitize debug output to remove sensitive data
   - Add `--insecure` flag with warnings for dev use

2. **Error Handling**
   - Add trap handlers for cleanup (EXIT, ERR)
   - Standardize exit codes across all scripts
   - Implement retry logic with exponential backoff
   - Add timeout handling for all API calls

3. **Input Validation**
   - Add regex validation for IPs, VM IDs, disk sizes
   - Validate Proxmox resources exist before operations
   - Check file paths and permissions

### Phase 2: Code Quality & Maintainability (Weeks 3-4) 🟡
**Goal**: Improve code organization and reduce technical debt

1. **Code Refactoring**
   - Create `lib/common.sh` with shared functions
   - Extract authentication logic
   - Centralize debug and logging functions
   - Remove code duplication

2. **Configuration Management**
   - Implement `.proxmox.conf` support
   - Add environment variable support
   - Implement config precedence (CLI > env > file > defaults)
   - Add `--show-config` flag

3. **Logging & Debugging**
   - Implement structured logging with levels
   - Add timestamps to all log output
   - Create `--verbose` and `--debug-safe` modes
   - Add log file support

### Phase 3: Performance & Testing (Weeks 5-6) 🟡
**Goal**: Optimize operations and add test coverage

1. **Performance Optimization**
   - Optimize API polling with exponential backoff
   - Reduce redundant API calls
   - Add request batching where possible
   - Implement caching for repeated queries

2. **Testing Infrastructure**
   - Add dry-run mode (`--dry-run`)
   - Create validation mode for pre-flight checks
   - Build test suite with mock API responses
   - Add integration tests

3. **Documentation**
   - Update README with new features
   - Add troubleshooting guide
   - Create usage examples
   - Document security best practices

### Phase 4: Feature Enhancement (Weeks 7-8) 🟢
**Goal**: Add features that improve user experience

1. **User Experience**
   - Add interactive mode
   - Implement progress indicators
   - Add bash/zsh completion
   - Improve help text and error messages

2. **Advanced Features**
   - Template versioning
   - Bulk operations support
   - VM snapshot management
   - Advanced network configurations

3. **Integration**
   - CI/CD pipeline examples
   - Webhook support
   - Monitoring integration

---

## Quick Wins (Can be implemented immediately)

### 1. Create Common Library (1-2 hours)
```bash
# lib/common.sh
#!/bin/bash
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROXMOX_PORT="${PROXMOX_PORT:-8006}"

# Shared functions
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$1] ${@:2}" >&2; }
log_info() { log "INFO" "$@"; }
log_error() { log "ERROR" "$@"; }
```

### 2. Add Config File Support (2-3 hours)
```bash
# .proxmox.conf
PVE_HOST=10.17.1.12
PVE_USER=root@pam
NODE_NAME=pve02
STORAGE_NAME=vm_data

# In scripts:
[[ -f .proxmox.conf ]] && source .proxmox.conf
```

### 3. Add Trap Handlers for Cleanup (1 hour)
```bash
trap cleanup EXIT ERR
cleanup() {
    [[ -d "$TEMP_FS_DIR" ]] && rm -rf "$TEMP_FS_DIR"
    [[ -d "$TEMP_ISO_DIR" ]] && rm -rf "$TEMP_ISO_DIR"
}
```

### 4. Implement Password from Environment (30 minutes)
```bash
# Instead of requiring --password, check env var first
PVE_PASSWORD="${PVE_PASSWORD:-}"
if [[ -z "$PVE_PASSWORD" ]]; then
    read -s -p "Enter Proxmox password: " PVE_PASSWORD
    echo
fi
```

### 5. Add IP Validation Function (1 hour)
```bash
validate_ip() {
    local ip="$1"
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
        log_error "Invalid IP address format: $ip"
        return 1
    fi
}
```

---

## Success Metrics

### Security
- ✅ No passwords in process list
- ✅ No SSL certificate bypass in production
- ✅ No sensitive data in debug logs

### Reliability
- ✅ All API errors handled gracefully
- ✅ Temp files cleaned up on any exit
- ✅ Retry logic for transient failures

### Code Quality
- ✅ <10% code duplication
- ✅ All functions have error handling
- ✅ Consistent coding standards

### Testing
- ✅ 80%+ test coverage
- ✅ All scripts pass shellcheck
- ✅ Integration tests pass

### User Experience
- ✅ Clear error messages with solutions
- ✅ <5 second feedback for all operations
- ✅ Comprehensive documentation
