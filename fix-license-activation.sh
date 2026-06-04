#!/usr/bin/env bash
#
# fix-license-activation.sh — Bypass n8n license activation failures on Node.js ≥26
#
# On Node.js 26+, n8n's internal HTTP client (undici) can fail to connect to
# the license server with "Connection Error: fetch failed" — even though normal
# curl / Node.js requests work fine. This script works around the issue by:
#
#   1. Obtaining n8n's instance ID (device fingerprint) from the running instance
#   2. Activating the license via a direct external HTTP call to license.n8n.io
#   3. Injecting the returned certificate into n8n's SQLite database
#   4. Prompting you to restart n8n so it picks up the new license
#
# Usage:
#   ./fix-license-activation.sh <LICENSE_KEY>                         # prompts for credentials
#   ./fix-license-activation.sh <LICENSE_KEY> --email you@example.com  # prompts for password only
#   ./fix-license-activation.sh <LICENSE_KEY> --email you@example.com --password "yourpass"
#
# Requirements:
#   - n8n installed and running (or --n8n-db pointing to its database)
#   - Owner account credentials (email + password)
#   - Node.js and sqlite3 available
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
N8N_LICENSE_SERVER="https://license.n8n.io/v1/activate"
N8N_DEFAULT_PORT=5678

# ---------------------------------------------------------------------------
# ANSI colors
# ---------------------------------------------------------------------------
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[0;31m'
C_CYAN='\033[0;36m'

info()    { echo -e "${C_GREEN}[INFO]${C_RESET}  $*"; }
warn()    { echo -e "${C_YELLOW}[WARN]${C_RESET}  $*"; }
error()   { echo -e "${C_RED}[ERROR]${C_RESET} $*"; }
banner()  { echo -e "${C_CYAN}${C_BOLD}$*${C_RESET}"; }

# ---------------------------------------------------------------------------
# Helper: join array by delimiter
# ---------------------------------------------------------------------------
join_by() { local d=$1; shift; echo -n "$1"; shift; printf "%s" "${@/#/$d}"; }

# ---------------------------------------------------------------------------
# Print usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") <LICENSE_KEY> [options]

Bypass n8n license activation failures on Node.js ≥26.

Arguments:
  LICENSE_KEY    Your n8n license key (required)

Options:
  --email EMAIL     Owner account email (prompts if not provided)
  --password PASS   Owner account password (prompts securely if not provided)
  --n8n-url URL     n8n instance URL (default: http://localhost:5678)
  --n8n-db PATH     Path to n8n SQLite database (auto-detected if omitted)
  --restart         Automatically restart n8n after activation
  --help            Show this help message

Examples:
  $(basename "$0") "abc123-def456-..."
  $(basename "$0") "abc123-def456-..." --email admin@example.com
  $(basename "$0") "abc123-def456-..." --email admin@example.com --password "s3cret"
  $(basename "$0") "abc123-def456-..." --n8n-db ~/.n8n/database.sqlite
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
LICENSE_KEY=""
OWNER_EMAIL=""
OWNER_PASSWORD=""
N8N_URL="http://localhost:${N8N_DEFAULT_PORT}"
N8N_DB=""
DO_RESTART=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            ;;
        --email)
            OWNER_EMAIL="$2"
            shift 2
            ;;
        --password)
            OWNER_PASSWORD="$2"
            shift 2
            ;;
        --n8n-url)
            N8N_URL="$2"
            shift 2
            ;;
        --n8n-db)
            N8N_DB="$2"
            shift 2
            ;;
        --restart)
            DO_RESTART=true
            shift
            ;;
        -*)
            error "Unknown option: $1"
            usage
            ;;
        *)
            if [[ -z "$LICENSE_KEY" ]]; then
                LICENSE_KEY="$1"
            else
                error "Unexpected argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
banner '╔══════════════════════════════════════════════════════════════╗'
banner '║          n8n License Activation Fix — Node.js ≥26           ║'
banner '╚══════════════════════════════════════════════════════════════╝'
echo ''

if [[ -z "$LICENSE_KEY" ]]; then
    error "License key is required."
    echo "  Usage: $(basename "$0") <LICENSE_KEY> [options]"
    echo "  Run with --help for full usage."
    exit 1
fi
info "License key: ${LICENSE_KEY:0:12}...${LICENSE_KEY: -4}"

# Node.js
if ! command -v node &>/dev/null; then
    error "Node.js is not installed. n8n requires Node.js."
    exit 1
fi
info "Node.js: $(node --version)"

# sqlite3
if command -v sqlite3 &>/dev/null; then
    HAS_SQLITE3=true
    info "sqlite3: available"
else
    HAS_SQLITE3=false
    warn "sqlite3 not found in PATH. Will try JavaScript-based SQLite."
fi

# ---------------------------------------------------------------------------
# Auto-detect n8n database
# ---------------------------------------------------------------------------
if [[ -z "$N8N_DB" ]]; then
    # Common locations
    for candidate in \
        "$HOME/.n8n/database.sqlite" \
        "$HOME/.config/n8n/database.sqlite" \
        "/var/lib/n8n/database.sqlite"; do
        if [[ -f "$candidate" ]]; then
            N8N_DB="$candidate"
            break
        fi
    done
fi

if [[ -n "$N8N_DB" ]]; then
    info "n8n database: $N8N_DB"
else
    warn "Could not locate n8n database automatically."
    warn "Provide it with --n8n-db PATH or ensure n8n has been started at least once."
fi

# ---------------------------------------------------------------------------
# Check if n8n is running
# ---------------------------------------------------------------------------
N8N_RUNNING=false
if command -v ss &>/dev/null; then
    N8N_PORT=$(echo "$N8N_URL" | sed -E 's|.*:([0-9]+)$|\1|')
    if ss -tlnp 2>/dev/null | grep -q ":${N8N_PORT:-5678} "; then
        N8N_RUNNING=true
        info "n8n detected: running on ${N8N_URL}"
    fi
elif command -v curl &>/dev/null; then
    if curl -sf "${N8N_URL}/healthz" &>/dev/null; then
        N8N_RUNNING=true
        info "n8n detected: running on ${N8N_URL}"
    fi
fi

# ---------------------------------------------------------------------------
# Get owner credentials (interactive prompt if not provided)
# ---------------------------------------------------------------------------
get_credentials() {
    if [[ -z "$OWNER_EMAIL" ]]; then
        echo ''
        read -r -p "  Owner email: " OWNER_EMAIL
    fi
    if [[ -z "$OWNER_PASSWORD" ]]; then
        echo ''
        read -r -s -p "  Owner password: " OWNER_PASSWORD
        echo ''
    fi
}

# ---------------------------------------------------------------------------
# Step 1: Get instance ID from running n8n
# ---------------------------------------------------------------------------
get_instance_id() {
    local login_resp login_http instance_id

    # Login to n8n API
    info "Logging in to n8n at ${N8N_URL}..."
    login_resp=$(curl -s -X POST "${N8N_URL}/rest/login" \
        -H "Content-Type: application/json" \
        -d "$(cat <<JSON
{"emailOrLdapLoginId": "${OWNER_EMAIL}", "password": "${OWNER_PASSWORD}"}
JSON
)" \
        -c /tmp/n8n-fix-cookies.$$ 2>/dev/null)

    if ! echo "$login_resp" | python3 -c "import sys,json; sys.exit(0 if 'data' in json.load(sys.stdin) else 1)" 2>/dev/null; then
        local msg
        msg=$(echo "$login_resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message','login failed'))" 2>/dev/null || echo "login failed")
        error "Login failed: ${msg}"
        return 1
    fi
    info "Login successful"

    # Get instance ID from settings
    instance_id=$(curl -s "${N8N_URL}/rest/settings" \
        -b /tmp/n8n-fix-cookies.$$ 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('instanceId',''))" 2>/dev/null || true)

    if [[ -z "$instance_id" ]]; then
        error "Could not retrieve instance ID from n8n API."
        error "Make sure your account has owner privileges."
        return 1
    fi

    echo "$instance_id"
    return 0
}

# ---------------------------------------------------------------------------
# Step 2: Activate license via external HTTP call (bypasses n8n's broken fetch)
# ---------------------------------------------------------------------------
activate_license() {
    local instance_id="$1"
    local result_json license_key_cert x509_cert base64_cert

    info "Activating license with fingerprint: ${instance_id:0:16}..."

    # Use Node.js to make the HTTP request (bypasses n8n's broken undici)
    result_json=$(node -e "
const http = require('https');
const data = JSON.stringify({
  reservationId: '${LICENSE_KEY}',
  tenantId: 1,
  productIdentifier: 'n8n',
  deviceFingerprint: '${instance_id}'
});

const options = {
  hostname: 'license.n8n.io',
  path: '/v1/activate',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(data),
    'User-Agent': 'n8n-license-fix-script'
  },
  timeout: 30000
};

const req = http.request(options, (res) => {
  let body = '';
  res.on('data', (chunk) => body += chunk);
  res.on('end', () => {
    if (res.statusCode === 200) {
      try {
        const parsed = JSON.parse(body);
        if (parsed.licenseKey && parsed.x509) {
          const certContainer = JSON.stringify({licenseKey: parsed.licenseKey, x509: parsed.x509});
          const base64 = Buffer.from(certContainer, 'utf8').toString('base64');
          process.stdout.write(base64);
          process.exit(0);
        } else {
          console.error('License server returned incomplete response');
          process.exit(1);
        }
      } catch (e) {
        console.error('Failed to parse response:', e.message);
        process.exit(1);
      }
    } else if (res.statusCode === 400) {
      console.error('License server rejected request:', body.substring(0, 200));
      process.exit(1);
    } else {
      console.error('License server returned HTTP', res.statusCode);
      process.exit(1);
    }
  });
});

req.on('error', (e) => {
  console.error('Connection Error:', e.message);
  process.exit(1);
});

req.on('timeout', () => {
  req.destroy();
  console.error('Connection timed out after 30s');
  process.exit(1);
});

req.write(data);
req.end();
" 2>&1)

    if [[ $? -ne 0 ]]; then
        error "License activation failed."
        error "Response: ${result_json}"
        return 1
    fi

    echo "$result_json"
    info "License activated successfully by license server"
    return 0
}

# ---------------------------------------------------------------------------
# Step 3: Store license cert in n8n database
# ---------------------------------------------------------------------------
store_license_cert() {
    local base64_cert="$1"
    local db_path="$2"

    if [[ -z "$db_path" || ! -f "$db_path" ]]; then
        # Try to find the DB one more time
        if [[ -f "$HOME/.n8n/database.sqlite" ]]; then
            db_path="$HOME/.n8n/database.sqlite"
        elif [[ -f "$HOME/.config/n8n/database.sqlite" ]]; then
            db_path="$HOME/.config/n8n/database.sqlite"
        else
            error "Cannot locate n8n database file."
            error "Please provide it with --n8n-db PATH"
            return 1
        fi
    fi

    info "Storing license certificate in: ${db_path}"

    if $HAS_SQLITE3; then
        # Escape single quotes for SQLite
        local escaped
        escaped=$(echo "$base64_cert" | sed "s/'/''/g")
        sqlite3 "$db_path" "INSERT OR REPLACE INTO settings (key, value, loadOnStartup) VALUES ('license.cert', '${escaped}', 0);" 2>/dev/null
        local rc=$?
        if [[ $rc -ne 0 ]]; then
            error "Failed to write to database (sqlite3 exit code: ${rc})."
            error "Ensure n8n is stopped and the file is writable."
            return 1
        fi
    else
        # Use Node.js as fallback
        node -e "
const fs = require('fs');
const { execSync } = require('child_process');
const dbPath = '${db_path}';
const cert = fs.readFileSync('/dev/stdin', 'utf8').trim();
const escaped = cert.replace(/'/g, \"''\");
const sql = \"INSERT OR REPLACE INTO settings (key, value, loadOnStartup) VALUES ('license.cert', '\" + escaped + \"', 0);\";
try {
    execSync('sqlite3 \"' + dbPath + '\" ' + JSON.stringify(sql), { shell: true, timeout: 10000 });
} catch (e) {
    console.error('Failed to write via sqlite3:', e.message);
    process.exit(1);
}
" <<< "$base64_cert" 2>&1

        if [[ $? -ne 0 ]]; then
            return 1
        fi
    fi

    # Verify the write
    local stored
    stored=$(sqlite3 "$db_path" "SELECT length(value) FROM settings WHERE key = 'license.cert';" 2>/dev/null || echo "0")
    if [[ "$stored" -gt 0 ]]; then
        info "License certificate stored (${stored} bytes)"
    else
        error "License certificate was not stored in the database."
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Step 4: Restart n8n (optional) or tell user
# ---------------------------------------------------------------------------
restart_n8n() {
    info "Restarting n8n..."

    # Stop n8n
    local n8n_pids
    n8n_pids=$(pgrep -f "node.*n8n" 2>/dev/null || true)
    if [[ -n "$n8n_pids" ]]; then
        info "Stopping n8n (PID(s): ${n8n_pids//$'\n'/ })..."
        kill -TERM $n8n_pids 2>/dev/null || true
        sleep 3
        # Force kill if still running
        n8n_pids=$(pgrep -f "node.*n8n" 2>/dev/null || true)
        if [[ -n "$n8n_pids" ]]; then
            kill -9 $n8n_pids 2>/dev/null || true
            sleep 1
        fi
    fi

    # Start n8n
    if command -v n8n &>/dev/null; then
        info "Starting n8n..."
        nohup n8n start > /tmp/n8n-fix-restart.log 2>&1 &
        local new_pid=$!
        sleep 5

        # Wait for it to be ready
        for i in $(seq 1 15); do
            if command -v ss &>/dev/null && ss -tlnp 2>/dev/null | grep -q ':5678'; then
                info "n8n is running (PID: ${new_pid})"
                info "Web UI: http://localhost:5678"
                return 0
            fi
            sleep 1
        done

        warn "n8n may not be ready yet. Check with: ss -tlnp | grep 5678"
        warn "Or manually start: n8n start"
    else
        warn "n8n command not found. Start it manually."
    fi
}

# ---------------------------------------------------------------------------
# Verify license activation
# ---------------------------------------------------------------------------
verify_license() {
    local login_resp

    info "Verifying license activation..."

    login_resp=$(curl -s -X POST "${N8N_URL}/rest/login" \
        -H "Content-Type: application/json" \
        -d "$(cat <<JSON
{"emailOrLdapLoginId": "${OWNER_EMAIL}", "password": "${OWNER_PASSWORD}"}
JSON
)" \
        -c /tmp/n8n-fix-cookies-verify.$$ 2>/dev/null)

    if echo "$login_resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('role',''))" 2>/dev/null | grep -q "owner"; then
        local plan_name
        plan_name=$(curl -s "${N8N_URL}/rest/license" \
            -b /tmp/n8n-fix-cookies-verify.$$ 2>/dev/null | \
            python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('license',{}).get('planName','unknown'))" 2>/dev/null || echo "unknown")

        if [[ "$plan_name" != "Community" && -n "$plan_name" ]]; then
            info "✅ License verified: plan = '${plan_name}'"
            return 0
        else
            warn "License still shows plan '${plan_name}'."
            warn "Try restarting n8n manually."
            return 1
        fi
    else
        warn "Could not verify license (login may have failed)."
        warn "Check the license status in the n8n UI at ${N8N_URL}/settings/usage"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
cleanup() {
    rm -f /tmp/n8n-fix-cookies.$$ /tmp/n8n-fix-cookies-verify.$$ /tmp/n8n-fix-cert.$$
}

trap cleanup EXIT

# ===========================================================================
# Main flow
# ===========================================================================

# --- If n8n not running and DB not found, we cannot proceed ---
if ! $N8N_RUNNING && [[ -z "$N8N_DB" ]]; then
    error "n8n is not running and the database could not be found."
    error "Please start n8n first, then re-run this script."
    error "Or provide the database path with --n8n-db PATH"
    exit 1
fi

# --- Prompt for credentials if n8n is running (we need them for instance ID) ---
if $N8N_RUNNING; then
    get_credentials

    # Step 1: Get instance ID
    echo ''
    banner '-- Step 1/4: Getting instance ID from n8n ...'
    INSTANCE_ID=$(get_instance_id)
    if [[ $? -ne 0 || -z "$INSTANCE_ID" ]]; then
        exit 1
    fi
    info "Instance ID: ${INSTANCE_ID:0:16}..."
    echo ''

    # Step 2: Activate license
    banner '-- Step 2/4: Activating license with license server ...'
    BASE64_CERT=$(activate_license "$INSTANCE_ID")
    if [[ $? -ne 0 || -z "$BASE64_CERT" ]]; then
        error "License activation failed. Check your license key."
        exit 1
    fi
    echo "$BASE64_CERT" > /tmp/n8n-fix-cert.$$
    info "Certificate received (${#BASE64_CERT} bytes encoded)"
    echo ''

    # Step 3: Store in database
    banner '-- Step 3/4: Storing certificate in database ...'
    if ! store_license_cert "$BASE64_CERT" "$N8N_DB"; then
        exit 1
    fi
    echo ''

    # Step 4: Restart or notify
    banner '-- Step 4/4: Finalizing ...'
    if $DO_RESTART; then
        restart_n8n
        sleep 5
        verify_license || true
    else
        info "License certificate has been stored."
        echo ''
        info "To apply the license:"
        info "  1. Restart n8n (Ctrl+C to stop, then ./start-n8n.sh)"
        info "  2. Verify at: ${N8N_URL}/settings/usage"
        if $N8N_RUNNING; then
            warn "  n8n is still running with the old license."
            warn "  A restart is required to pick up the new certificate."
        fi
    fi

else
    # --- Offline mode: n8n not running, but we have the DB ---
    info "n8n is not running — using offline activation."
    warn "Offline activation requires a known instance ID."
    echo ''
    warn "If you know your n8n instance ID, provide it via --instance-id (not yet supported)."
    warn "Otherwise, start n8n first and then run this script."
    echo ''

    # Try to read instance ID from database
    if [[ -n "$N8N_DB" ]] && $HAS_SQLITE3; then
        local stored_id
        stored_id=$(sqlite3 "$N8N_DB" "SELECT value FROM settings WHERE key = 'instance.id';" 2>/dev/null || true)
        if [[ -n "$stored_id" ]]; then
            info "Found stored instance ID: ${stored_id:0:16}..."
            INSTANCE_ID="$stored_id"
        fi
    fi

    if [[ -z "${INSTANCE_ID:-}" ]]; then
        error "Cannot proceed without instance ID."
        error "Start n8n and re-run this script."
        exit 1
    fi

    # Proceed with activation and DB storage
    echo ''
    banner '-- Activating license (offline) ...'
    BASE64_CERT=$(activate_license "$INSTANCE_ID")
    if [[ $? -ne 0 || -z "$BASE64_CERT" ]]; then
        exit 1
    fi
    echo ''

    banner '-- Storing certificate ...'
    store_license_cert "$BASE64_CERT" "$N8N_DB"
    echo ''

    info "License certificate stored."
    info "Start n8n to apply the license."
fi

# ===========================================================================
# Final summary
# ===========================================================================
echo ''
banner '╔══════════════════════════════════════════════════════════════╗'
banner '║                    Done                                      ║'
banner '╚══════════════════════════════════════════════════════════════╝'
echo ''

if $N8N_RUNNING && ! $DO_RESTART; then
    echo -e "  ${C_YELLOW}Important:${C_RESET} Restart n8n to apply the license."
    echo ''
    echo -e "  ${C_GREEN}Stop:${C_RESET}  Ctrl+C in the n8n terminal, or:"
    echo -e "         pkill -f 'n8n start'"
    echo ''
    echo -e "  ${C_GREEN}Start:${C_RESET} cd n8n-workspace && ./start-n8n.sh"
    echo ''
    echo -e "  ${C_GREEN}Verify:${C_RESET} ${N8N_URL}/settings/usage"
elif $DO_RESTART; then
    echo -e "  ${C_GREEN}n8n restarted with the new license.${C_RESET}"
    echo -e "  ${C_GREEN}Web UI:${C_RESET} ${N8N_URL}"
fi
echo ''
