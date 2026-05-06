#!/usr/bin/env bash
# Manual integration test suite for devcontainer.network.allowedHosts.
#
# Uses the devcontainer CLI to start the test fixture (tests/fixtures/allowed-hosts),
# runs connectivity checks inside the container, then tears it down.
#
# Prerequisites:
#   - devcontainer CLI  →  add "devcontainer" to devcontainer.tweaks in devenv.local.nix
#   - podman or docker available on PATH
#
# Usage:
#   ./tests/test-allowed-hosts.sh           # run tests, remove container on exit
#   ./tests/test-allowed-hosts.sh --keep    # keep container running after tests
#   ./tests/test-allowed-hosts.sh --dev     # dev mode: skip sudo removal, allow EXTRA_ALLOWED_HOSTS
#   ./tests/test-allowed-hosts.sh --dev --keep

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/allowed-hosts"
KEEP=""
DEV=""
for arg in "$@"; do
  case "$arg" in
    --keep) KEEP="--keep" ;;
    --dev)  DEV="--dev"   ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

detect_runtime() {
  if command -v podman >/dev/null 2>&1; then
    echo "podman"
  elif command -v docker >/dev/null 2>&1; then
    echo "docker"
  else
    echo ""
  fi
}

RUNTIME="$(detect_runtime)"

# Build --docker-path flag for the devcontainer CLI when using podman
if [ "$RUNTIME" = "podman" ]; then
  DOCKER_PATH_ARG="--docker-path $(command -v podman)"
else
  DOCKER_PATH_ARG=""
fi

remove_container() {
  [ -n "$RUNTIME" ] || return 0
  local label="devcontainer.local_folder=$(realpath "$FIXTURE_DIR")"
  local cids
  cids="$($RUNTIME ps -aq --filter "label=$label" 2>/dev/null || true)"
  if [ -n "$cids" ]; then
    # shellcheck disable=SC2086
    $RUNTIME rm -f $cids >/dev/null 2>&1 || true
  fi
}

cleanup() {
  if [ "$KEEP" != "--keep" ]; then
    echo ""
    echo "Removing test container..."
    remove_container
  else
    echo ""
    echo -e "${YELLOW}Container kept running (--keep).${NC}"
    echo "  Workspace: $FIXTURE_DIR"
    echo "  To inspect: devcontainer exec $DOCKER_PATH_ARG --workspace-folder $FIXTURE_DIR -- bash"
    echo "  To remove:  $RUNTIME rm -f \$($RUNTIME ps -aq --filter label=devcontainer.local_folder)"
  fi
}

run_test() {
  local desc="$1" expected="$2" cmd="$3"
  # Pad description to fixed width for aligned output
  printf "  %-60s" "$desc"
  local actual="fail"
  # shellcheck disable=SC2086
  if devcontainer exec $DOCKER_PATH_ARG --workspace-folder "$FIXTURE_DIR" -- sh -c "$cmd" \
       >/dev/null 2>&1; then
    actual="pass"
  fi
  if [ "$actual" = "$expected" ]; then
    echo -e " ${GREEN}PASS${NC}"
    PASS=$((PASS + 1))
  else
    echo -e " ${RED}FAIL${NC} (expected=$expected, got=$actual)"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

if ! command -v devcontainer >/dev/null 2>&1; then
  echo -e "${RED}ERROR: devcontainer CLI not found.${NC}"
  echo "  Add \"cli\" to devcontainer.tweaks in your devenv.local.nix, re-enter the shell,"
  echo "  then re-run this script."
  exit 1
fi

if [ -z "$RUNTIME" ]; then
  echo -e "${RED}ERROR: neither podman nor docker found on PATH.${NC}"
  exit 1
fi

# ---------------------------------------------------------------------------
# Start container
# ---------------------------------------------------------------------------

trap cleanup EXIT

echo -e "${BOLD}=== devcontainer allowedHosts integration tests ===${NC}"
echo "  Fixture : $FIXTURE_DIR"
echo "  Runtime : $RUNTIME"
echo "  Policy  : outbound allowed to github.com only"
[ -z "$DEV" ] || echo -e "  Mode    : ${YELLOW}dev (sudo kept, EXTRA_ALLOWED_HOSTS supported)${NC}"
echo ""
echo "Starting devcontainer..."
# shellcheck disable=SC2086
devcontainer up $DOCKER_PATH_ARG \
  ${DEV:+--remote-env FIREWALL_DEV=1} \
  --workspace-folder "$FIXTURE_DIR" \
  --remove-existing-container

# postStartCommand (firewall setup) runs asynchronously after 'up' returns.
# Give it a moment to finish before running tests.
echo ""
echo "Waiting for postStartCommand (firewall setup) to complete..."
sleep 4

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}--- Permitted traffic ---${NC}"

run_test "loopback 127.0.0.1 reachable (iptables ACCEPT, not DROP)" \
  "pass" \
  "timeout 1 bash -c 'echo > /dev/tcp/127.0.0.1/1' 2>/dev/null; [ \$? -ne 124 ]"

run_test "DNS: github.com resolves (getent hosts)" \
  "pass" \
  "getent hosts github.com"

run_test "DNS: google.com still resolves (DNS is permitted)" \
  "pass" \
  "getent hosts google.com"

run_test "github.com HTTPS reachable (allowed host)" \
  "pass" \
  "curl -sf --max-time 15 --retry 2 https://github.com >/dev/null"

echo ""
echo -e "${BOLD}--- Blocked traffic ---${NC}"

run_test "google.com HTTPS blocked (not in allowlist)" \
  "fail" \
  "curl -sf --connect-timeout 5 --max-time 6 https://www.google.com >/dev/null"

run_test "example.com HTTPS blocked (not in allowlist)" \
  "fail" \
  "curl -sf --connect-timeout 5 --max-time 6 https://example.com >/dev/null"

run_test "1.1.1.1 direct TCP blocked (not in allowlist)" \
  "fail" \
  "timeout 5 sh -c 'echo | nc -w3 1.1.1.1 443' 2>/dev/null"

run_test "api.openai.com HTTPS blocked (not in allowlist)" \
  "fail" \
  "curl -sf --connect-timeout 5 --max-time 6 https://api.openai.com >/dev/null"

echo ""
echo -e "${BOLD}--- Inbound safety ---${NC}"

run_test "firewall does not install INPUT hook (inbound remains runtime default)" \
  "fail" \
  "nft list table inet devcontainer | grep -q 'hook input'"

echo ""
echo -e "${BOLD}--- Security: sudo removal ---${NC}"

if [ -n "$DEV" ]; then
  echo -e "  ${YELLOW}Skipped (dev mode — sudo intentionally kept)${NC}"
else
  run_test "sudo is no longer available (passwordless sudo removed)" \
    "fail" \
    "sudo true 2>/dev/null"

  run_test "cannot delete nftables table without sudo" \
    "fail" \
    "nft delete table inet devcontainer 2>/dev/null || sudo nft delete table inet devcontainer 2>/dev/null"
fi

# ---------------------------------------------------------------------------
# Firewall rule dump (informational)
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}--- Firewall state (informational) ---${NC}"
# shellcheck disable=SC2086
devcontainer exec $DOCKER_PATH_ARG --workspace-folder "$FIXTURE_DIR" -- \
  sh -c "nft list ruleset 2>/dev/null || echo '  (nft not available or no rules)'" \
  2>/dev/null | sed 's/^/    /' || true

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}=== Results ===${NC}"
echo -e "  Passed: ${GREEN}${PASS}${NC}   Failed: ${RED}${FAIL}${NC}"
echo ""

[ "$FAIL" -eq 0 ]
