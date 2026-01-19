# ROADMAP.md

## Current State (Updated January 2026)

### ✅ Completed Improvements
This repository has undergone significant refactoring and security hardening:

**Security & Stability:**
- ✅ SSL certificate validation (removed `-k` bypass, added `--ca-cert` and `--insecure` options)
- ✅ Secure credential handling (password prompts, environment variable support, redacted debug output)
- ✅ Trap handlers for cleanup on EXIT and ERR signals
- ✅ Standardized exit codes (1=user, 2=system, 3=API)
- ✅ Exponential backoff retry logic (2s→30s, max 3 attempts)

**Code Quality:**
- ✅ Shared library `lib/common.sh` with 20+ common functions
- ✅ Consolidated authentication, validation, logging, and API helpers
- ✅ Input validation (IPv4, numeric, disk resize patterns, file permissions)
- ✅ Structured logging with timestamps (INFO, WARN, ERROR, DEBUG levels)
- ✅ Shellcheck compliance (all scripts pass validation)

**Features:**
- ✅ Unified progress indicators with step counters and visual separators
- ✅ Skip-bridge-indexes option for selective network configuration
- ✅ Environment variable support for all configuration
- ✅ Comprehensive error handling with actionable messages

**Code Metrics:**
- 351 lines consolidated from scripts into shared library
- 66 lines removed through API error handling consolidation
- 170 lines added for professional progress indicators
- Net reduction of ~250+ duplicate lines across codebase

## Priority Levels

### 🔴 High Priority (Security & Stability)
Critical issues that should be addressed before production use.

### 🟡 Medium Priority (Quality & Efficiency)
Important improvements for maintainability and performance.

### 🟢 Low Priority (Features & UX)
Enhancements that add value but aren't blocking.

---

## Remaining Improvements

### 1. Performance Optimizations 🟡
- Parallelize independent operations where possible
- Optimize polling intervals for specific operations
- Implement async operations for non-blocking tasks
- Add caching for repeated queries

### 2. Additional Code Quality Improvements 🟡
- Add more comprehensive unit tests
- Implement automated testing in CI/CD pipeline
- Add code coverage reporting
- Further reduce code duplication opportunities

### 3. Additional Security Enhancements 🟡
- **Rate limiting for API calls**
  - Add configurable delays between API requests
  - Implement request throttling to prevent API overload
- **Audit logging**
  - Log all API operations with timestamps
  - Track who performed what operations
  - Optional syslog integration
- **Token-based authentication**
  - Support Proxmox API tokens as alternative to passwords

### 4. Enhanced Configuration Management 🟡
- **Advanced config file support**
  - Support YAML/JSON format for complex configurations
  - Support multiple profiles (dev, staging, prod)
  - Config file locations: `~/.proxmox.conf`, `./.proxmox.conf`, custom path
- **Configuration validation and display**
  - Add `--show-config` flag to display effective configuration
  - Validate config file syntax before use
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
  - Useful for testing scripts before actual execution
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
  - Add confirmation prompts for destructive operations
- **Enhanced progress indicators**
  - Add ETA calculations for API operations
  - Real-time status updates
  - Animated spinners for operations without known duration (function exists but not yet used)
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

## Implementation Priorities

### Next Steps (High Value)
1. **Dry-run mode** - Low effort, high value for testing
2. **API token authentication** - Security improvement for automated workflows
3. **Configuration profiles** - Support dev/staging/prod environments
4. **Automated test suite** - Prevent regressions
5. **Interactive mode** - Better UX for manual operations

### Future Enhancements (Lower Priority)
- Template versioning and comparison
- Bulk operations support
- VM snapshot management
- Webhook support for integrations
- CI/CD pipeline examples
- Bash/Zsh completion scripts
- Advanced network configurations

---

## Development Notes

### Code Quality Standards
The codebase now maintains:
- ✅ All scripts pass shellcheck validation
- ✅ Consistent error handling patterns
- ✅ Shared library for common functionality
- ✅ Professional progress indicators
- ✅ Secure credential handling
- ✅ Input validation for all parameters

### Architecture Decisions
- **Shared library approach**: All common functionality consolidated in `lib/common.sh`
- **Configuration precedence**: CLI args → env vars → .env file → defaults
- **Exit code standards**: 1=user error, 2=system error, 3=API error
- **Retry strategy**: Exponential backoff (2s, 4s, 8s) with max 3 attempts

---

## Success Metrics

### Security ✅
- ✅ No passwords in process list (password prompting implemented)
- ✅ SSL certificate validation (--ca-cert and --insecure options available)
- ✅ Sensitive data redacted in debug logs

### Reliability ✅
- ✅ All API errors handled gracefully (check_api_error function)
- ✅ Temp files cleaned up on any exit (trap handlers implemented)
- ✅ Retry logic for transient failures (exponential backoff with 3 retries)

### Code Quality ✅
- ✅ Minimal code duplication (shared library with 20+ common functions)
- ✅ All functions have error handling
- ✅ All scripts pass shellcheck

### User Experience ✅
- ✅ Clear error messages with context
- ✅ Professional progress indicators with step tracking
- ✅ Comprehensive documentation (README and inline help)

### Testing
- ⚠️ Test coverage to be implemented
- ⚠️ Integration tests needed
- ⚠️ CI/CD pipeline to be added
