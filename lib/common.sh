#!/bin/bash

# Common helpers for Proxmox scripts
# - Provides simple logging with timestamps and levels
# - Establishes standardized exit codes
# - Sets up traps for ERR/EXIT to aid troubleshooting

set -o pipefail

EXIT_USER=1
EXIT_SYSTEM=2
EXIT_API=3

script_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  local level="$1"; shift
  local msg="$*"
  echo "$(script_timestamp) [${level}] ${msg}" >&2
}

log_info()  { log INFO  "$*"; }
log_warn()  { log WARN  "$*"; }
log_error() { log ERROR "$*"; }
log_debug() {
  if [[ "${DEBUG_MODE:-false}" == true ]]; then
    log DEBUG "$*"
  fi
}

handle_err() {
  local exit_code=$?
  local line=${1:-}
  log_error "Unhandled error (exit ${exit_code}) at line ${line:-?}."
  exit "${exit_code}"
}

handle_exit() {
  if [[ -n "${CLEANUP_FUNC:-}" && "$(type -t "${CLEANUP_FUNC:-}")" == function ]]; then
    "${CLEANUP_FUNC}"
  fi
}

setup_traps() {
  trap 'handle_exit' EXIT
  trap 'handle_err $LINENO' ERR
}
