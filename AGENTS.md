# AGENTS.md

This file provides guidelines for agentic coding agents operating in this repository.

## Build/Lint/Test Commands

Since these are bash scripts for Proxmox operations, there are no traditional build systems:
- No linting or type checking required for bash scripts
- Test commands would involve running the scripts with appropriate parameters
- Individual test execution is done by running specific bash script files with required arguments

## Code Style Guidelines

### Bash Scripting
- Use `#!/bin/bash` shebang at the top of all scripts
- Follow POSIX shell standards for maximum compatibility
- Use descriptive variable names (e.g., `PVE_HOST` instead of `H`)
- All variables should be declared with `local` inside functions
- Use `[[ ]]` for conditional tests instead of `[ ]`
- All error handling should use `exit 1` when appropriate
- Use functions to organize code logically

### Imports and Dependencies
- Only use standard bash built-ins (no external dependencies required)
- Use `curl` and `jq` for API interactions and JSON parsing
- Use `mkisofs` for ISO creation when needed

### Formatting
- No specific formatting rules enforced - follow existing conventions in the codebase
- Use consistent indentation (4 spaces) for readability

### Naming Conventions
- Variables in UPPERCASE with underscores (e.g., `PVE_HOST`)
- Functions in lowercase with underscores (e.g., `authenticate`)
- Constants should be all caps with underscores

### Error Handling
- All API calls should check for errors using jq parsing or exit code validation
- All scripts should validate required arguments at startup
- Use proper error messages with descriptive details for debugging

### Documentation
- All functions should have comments explaining their purpose and parameters
- Help text should be comprehensive and include all valid options

## Development Roadmap

For optimization plans and feature enhancements, please refer to the ROADMAP.md file in this repository which contains a detailed plan for improving these scripts.