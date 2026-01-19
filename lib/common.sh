#!/bin/bash

# Common helpers for Proxmox scripts
# - Provides simple logging with timestamps and levels
# - Establishes standardized exit codes
# - Sets up traps for ERR/EXIT to aid troubleshooting

set -o pipefail

EXIT_USER=1
EXIT_SYSTEM=2
EXIT_API=3
CURL_MAX_RETRIES=${CURL_MAX_RETRIES:-3}
CURL_BACKOFF_INITIAL=${CURL_BACKOFF_INITIAL:-2}
CURL_BACKOFF_MAX=${CURL_BACKOFF_MAX:-30}

bail() {
  local code="$1"; shift
  log_error "$*"
  exit "$code"
}

is_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
  for o in "$o1" "$o2" "$o3" "$o4"; do
    if (( o < 0 || o > 255 )); then
      return 1
    fi
  done
  return 0
}

validate_ipv4_or_bail() {
  local ip="$1"
  local context="$2"
  if ! is_ipv4 "$ip"; then
    bail "$EXIT_USER" "Invalid IPv4 address for ${context}: ${ip}"
  fi
}

validate_numeric_or_bail() {
  local value="$1"
  local context="$2"
  if [[ -z "$value" || ! "$value" =~ ^[0-9]+$ ]]; then
    bail "$EXIT_USER" "${context} must be a positive integer (got: '${value}')"
  fi
}

validate_disk_resize_or_bail() {
  local value="$1"
  local context="$2"
  if [[ -n "$value" && ! "$value" =~ ^\+[0-9]+[GM]?$ ]]; then
    bail "$EXIT_USER" "${context} must match +<number>[G|M], e.g., +10G (got: '${value}')"
  fi
}

require_file_readable() {
  local path="$1"
  local context="$2"
  if [[ -z "$path" || ! -f "$path" ]]; then
    bail "$EXIT_USER" "Missing or unreadable file for ${context}: ${path}"
  fi
}

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

curl_with_retries() {
  local attempt=1
  local delay="$CURL_BACKOFF_INITIAL"
  local output
  while true; do
    output=$(curl "${CURL_OPTS[@]}" "$@")
    local status=$?
    if [[ $status -eq 0 ]]; then
      echo "$output"
      return 0
    fi

    if (( attempt >= CURL_MAX_RETRIES )); then
      log_error "curl failed after ${attempt} attempts (status ${status})"
      return $status
    fi

    log_warn "curl failed (status ${status}), retrying in ${delay}s... (${attempt}/${CURL_MAX_RETRIES})"
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
    if (( delay > CURL_BACKOFF_MAX )); then
      delay=$CURL_BACKOFF_MAX
    fi
  done
}

debug_response() {
  local response="$1"
  if [[ "${DEBUG_MODE:-false}" == true ]]; then
    local redacted="$response"
    for secret in "$PVE_PASSWORD" "$PVE_TOKEN_SECRET" "$PVE_AUTH_COOKIE" "$CSRF_TOKEN"; do
      if [[ -n "$secret" ]]; then
        redacted=${redacted//"$secret"/"***REDACTED***"}
      fi
    done
    log_debug "API Response: $(echo "$redacted" | jq . 2>/dev/null || echo "$redacted")"
  fi
}

authenticate() {
  log_info "Authenticating with Proxmox server..."
  local response=$(curl_with_retries -X POST "$PROXMOX_API_URL/access/ticket" \
    --data-urlencode "username=$PVE_USER" \
    --data-urlencode "password=$PVE_PASSWORD" \
    -H "Content-Type: application/x-www-form-urlencoded")

  debug_response "$response"

  CSRF_TOKEN=$(echo "$response" | jq -r '.data.CSRFPreventionToken')
  PVE_AUTH_COOKIE=$(echo "$response" | jq -r '.data.ticket')

  if [[ -z "$CSRF_TOKEN" || -z "$PVE_AUTH_COOKIE" ]]; then
    bail "$EXIT_API" "Authentication failed. Unable to retrieve CSRF token or auth cookie."
  fi
  log_info "Authentication successful."
}

init_auth() {
  local auth_mode="${PVE_AUTH_MODE:-}"
  if [[ -z "$auth_mode" ]]; then
    if [[ -n "$PVE_TOKEN_ID" && -n "$PVE_TOKEN_SECRET" ]]; then
      auth_mode="token"
    else
      auth_mode="password"
    fi
  fi

  if [[ "$auth_mode" == "token" ]]; then
    if [[ -z "$PVE_USER" || -z "$PVE_TOKEN_ID" || -z "$PVE_TOKEN_SECRET" ]]; then
      bail "$EXIT_USER" "Token auth requires PVE_USER, PVE_TOKEN_ID, and PVE_TOKEN_SECRET."
    fi
    local token_id_full="$PVE_TOKEN_ID"
    if [[ "$token_id_full" != *"!"* ]]; then
      token_id_full="${PVE_USER}!${PVE_TOKEN_ID}"
    fi
    AUTH_HEADER_ARGS=(-H "Authorization: PVEAPIToken=${token_id_full}=${PVE_TOKEN_SECRET}")
  else
    if [[ -z "$PVE_PASSWORD" ]]; then
      prompt_for_password
    fi
    authenticate
    AUTH_HEADER_ARGS=(-H "CSRFPreventionToken: $CSRF_TOKEN" -H "Cookie: PVEAuthCookie=$PVE_AUTH_COOKIE")
  fi
}

wait_for_task() {
  local upid="$1"
  local task_name="$2"
  local timeout=${3:-300}
  local interval=${4:-5}
  local elapsed=0

  if [[ -z "$upid" || "$upid" == "null" ]]; then
    bail "$EXIT_API" "Missing task ID for ${task_name}."
  fi

  while (( elapsed < timeout )); do
    local response=$(curl_with_retries -X GET "$PROXMOX_API_URL/nodes/$NODE_NAME/tasks/$upid/status" \
      "${AUTH_HEADER_ARGS[@]}")

    debug_response "$response"

    local status=$(echo "$response" | jq -r '.data.status // empty')
    local exitstatus=$(echo "$response" | jq -r '.data.exitstatus // empty')

    if [[ "$status" == "stopped" ]]; then
      if [[ "$exitstatus" != "OK" ]]; then
        bail "$EXIT_API" "Task ${task_name} failed with status: ${exitstatus}"
      fi
      return 0
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  bail "$EXIT_SYSTEM" "Timeout waiting for task ${task_name} to complete."
}

prompt_for_password() {
  read -s -p "Enter Proxmox password: " PVE_PASSWORD
  echo
}
