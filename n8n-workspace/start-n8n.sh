#!/usr/bin/env bash
#
# start-n8n.sh — Convenience launcher for n8n
#
# Starts n8n with a colourful banner and graceful shutdown.
#
set -euo pipefail

# NOTE: License was activated via database cert.
# To reactivate with a different key, uncomment:
# export N8N_LICENSE_ACTIVATION_KEY="your-key-here"

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_GREEN='\033[0;32m'
C_CYAN='\033[0;36m'
C_YELLOW='\033[1;33m'

echo -e "${C_CYAN}${C_BOLD}"
echo '╔══════════════════════════════════════════════════════════╗'
echo '║                    n8n — Workflow Automation             ║'
echo '╚══════════════════════════════════════════════════════════╝'
echo -e "${C_RESET}"

# Get n8n version
N8N_VER=$(n8n --version 2>/dev/null || echo 'unknown')
echo -e "  ${C_GREEN}n8n version:${C_RESET}  ${N8N_VER}"
echo -e "  ${C_GREEN}Web UI:${C_RESET}       http://localhost:${N8N_PORT:-5678}"
echo -e "  ${C_YELLOW}Stop:${C_RESET}         Ctrl+C"
echo ''

# Graceful shutdown on SIGINT / SIGTERM
cleanup() {
    echo ''
    echo -e "${C_YELLOW}Shutting down n8n gracefully ...${C_RESET}"
    kill -INT "${n8n_pid}" 2>/dev/null || true
    wait "${n8n_pid}" 2>/dev/null || true
    echo -e "${C_GREEN}n8n stopped.${C_RESET}"
    exit 0
}
trap cleanup SIGINT SIGTERM

# Start n8n in background so we can trap signals
n8n start &
n8n_pid=$!
wait "$n8n_pid"
exit_code=$?

# If we get here, n8n exited on its own (not via signal)
echo -e "${C_GREEN}n8n exited (code: ${exit_code}).${C_RESET}"
exit $exit_code
