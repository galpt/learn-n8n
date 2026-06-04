#!/usr/bin/env bash
#
# setup-n8n.sh — n8n Installation & Workspace Setup
#
# Installs n8n on Arch-based Linux via paru (AUR),
# creates the workspace directory structure,
# and writes all workspace files.
#
# Usage:
#   ./setup-n8n.sh
#
# The script is idempotent — safe to re-run.
# Existing workspace files are never overwritten.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# ANSI color helpers
# ---------------------------------------------------------------------------
readonly C_RESET='\033[0m'
readonly C_BOLD='\033[1m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_RED='\033[0;31m'
readonly C_CYAN='\033[0;36m'

info()    { echo -e "${C_GREEN}[INFO]${C_RESET}  $*"; }
warn()    { echo -e "${C_YELLOW}[WARN]${C_RESET}  $*"; }
error()   { echo -e "${C_RED}[ERROR]${C_RESET} $*"; }
banner()  { echo -e "${C_CYAN}${C_BOLD}$*${C_RESET}"; }

# ---------------------------------------------------------------------------
# Guard: prevent running as root
# ---------------------------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
    error 'Do not run this script as root. Run it as a regular user with sudo access.'
    exit 1
fi

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
WORKSPACE_DIR="$HOME/Desktop/github/learn-n8n/n8n-workspace"
WORKFLOWS_DIR="$WORKSPACE_DIR/workflows"
CREDENTIALS_DIR="$WORKSPACE_DIR/credentials"

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
banner '╔══════════════════════════════════════════════════════════════╗'
banner '║              n8n Setup — Installation & Workspace           ║'
banner '╚══════════════════════════════════════════════════════════════╝'
echo ''

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

# 1. Arch-based OS
banner '-- Checking operating system ...'
if [[ -f /etc/arch-release ]]; then
    info "Arch-based OS detected ($(cat /etc/arch-release))"
else
    error 'This script is designed for Arch-based Linux distributions.'
    error 'No /etc/arch-release found. Aborting.'
    exit 1
fi

# 2. paru available
banner '-- Checking for paru (AUR helper) ...'
if command -v paru &>/dev/null; then
    info "paru found: $(paru --version 2>&1 | head -1)"
else
    error 'paru is not installed or not in PATH.'
    error 'Install it first: sudo pacman -S --needed base-devel git'
    error 'Then: git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si'
    exit 1
fi

# 3. Node.js >= 18.10
banner '-- Checking Node.js version ...'
if command -v node &>/dev/null; then
    node_version=$(node --version 2>&1 | sed 's/^v//')
    node_major="${node_version%%.*}"
    info "Node.js v${node_version} found"
    if [[ "$node_major" -lt 18 ]]; then
        error "Node.js >= 18.10 is required (found v${node_version})."
        exit 1
    fi
    # Parse minor version for 18.x (need >= 18.10)
    if [[ "$node_major" -eq 18 ]]; then
        node_minor="${node_version#*.}"
        node_minor="${node_minor%%.*}"
        if [[ "$node_minor" -lt 10 ]]; then
            error "Node.js >= 18.10 is required (found v${node_version})."
            exit 1
        fi
    fi

    # Warn about Node.js 26+ license activation bug
    if [[ "$node_major" -ge 26 ]]; then
        warn 'Node.js 26 detected: n8n license activation may fail'
        warn 'with "Connection Error: fetch failed" due to an undici'
        warn 'compatibility issue. If you encounter this, run:'
        warn '  ./fix-license-activation.sh <YOUR_LICENSE_KEY> --email you@example.com'
    fi
else
    error 'Node.js is not installed. Install it first, then re-run this script.'
    exit 1
fi

# 4. Port 5678 warning (non-fatal)
banner '-- Checking port 5678 ...'
if command -v ss &>/dev/null; then
    if ss -tlnp 2>/dev/null | grep -q ':5678\b'; then
        warn 'Port 5678 is already in use. n8n will fail to bind to it.'
        warn 'Set N8N_PORT to an alternative port before starting n8n.'
    else
        info 'Port 5678 is free'
    fi
elif command -v netstat &>/dev/null; then
    if netstat -tlnp 2>/dev/null | grep -q ':5678'; then
        warn 'Port 5678 is already in use. n8n will fail to bind to it.'
        warn 'Set N8N_PORT to an alternative port before starting n8n.'
    else
        info 'Port 5678 is free'
    fi
else
    warn 'Neither ss nor netstat found — skipping port check'
fi

echo ''

# ---------------------------------------------------------------------------
# Install n8n via paru (idempotent)
# ---------------------------------------------------------------------------
# Check sudo availability (paru needs it)
banner '-- Checking sudo access ...'
if ! sudo -v &>/dev/null; then
    error 'sudo authentication required. Run this script as a normal user with sudo access.'
    exit 1
fi
info 'sudo access confirmed'

banner '-- Installing / updating n8n via paru ...'
paru -S --noconfirm n8n
echo ''

# ---------------------------------------------------------------------------
# Verify installation
# ---------------------------------------------------------------------------
banner '-- Verifying n8n installation ...'
if command -v n8n &>/dev/null; then
    n8n_version=$(n8n --version 2>&1)
    info "n8n ${n8n_version} installed successfully"
else
    error 'n8n command not found after installation. Check PATH or re-run.'
    exit 1
fi
echo ''

# ---------------------------------------------------------------------------
# Create workspace directory structure
# ---------------------------------------------------------------------------
banner '-- Creating workspace directory structure ...'
mkdir -p "$WORKFLOWS_DIR"
mkdir -p "$CREDENTIALS_DIR"
info "Workspace root: $WORKSPACE_DIR"
info "Workflows:      $WORKFLOWS_DIR"
info "Credentials:    $CREDENTIALS_DIR"
echo ''

# ---------------------------------------------------------------------------
# Write workspace files (idempotent — skip if file exists)
# ---------------------------------------------------------------------------
banner '-- Writing workspace files (skipping existing) ...'
echo ''

# Helper: write a file only if it does not already exist
write_file() {
    local path="$1"
    if [[ -f "$path" ]]; then
        warn "Skipping existing file: $path"
        return 0
    fi
    # The file content is piped via heredoc from stdin
    # We use a temp file so we can write heredoc content
    cat > "$path"
    chmod 644 "$path"
    info "Created: $path"
}

write_executable() {
    local path="$1"
    if [[ -f "$path" ]]; then
        warn "Skipping existing file: $path"
        return 0
    fi
    cat > "$path"
    chmod 755 "$path"
    info "Created (executable): $path"
}

# --- start-n8n.sh ---
write_executable "$WORKSPACE_DIR/start-n8n.sh" << 'EOF'
#!/usr/bin/env bash
#
# start-n8n.sh — Convenience launcher for n8n
#
# Starts n8n with a colourful banner and graceful shutdown.
#
set -euo pipefail

# To set a license activation key, uncomment and set:
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
EOF

# --- README.md ---
write_file "$WORKSPACE_DIR/README.md" << 'EOF'
# n8n Workspace

## What is n8n?

[n8n](https://n8n.io) is a free and open-source workflow automation tool. It
lets you connect apps, services, and APIs together with a visual node-based
editor — no coding required (but fully extensible with code when you need it).

---

## Quick Start

### 1. Start n8n

```bash
./start-n8n.sh
```

Or directly:

```bash
n8n start
```

### 2. Open the Web UI

Navigate to [http://localhost:5678](http://localhost:5678) in your browser.

### 3. First-Time Setup

When you open n8n for the first time you will be asked to create an **owner
account**. Choose an email and a strong password. This account owns all
workflows, credentials, and settings.

### 4. Import the Starter Workflow

This workspace includes a starter workflow at:

```
workflows/hello-world.json
```

To import it:

1. Open the n8n web UI.
2. Click **Workflows** in the left sidebar.
3. Click the **Import** button (or drag-and-drop the JSON file onto the
   workflow list).
4. Open the imported workflow and click **Execute Workflow** to run it.

The workflow has three nodes:

- **Manual Trigger** — starts the workflow when you click "Execute Workflow"
- **Build Greeting** — a Code node that returns a greeting object
- **Respond** — returns the result to the web UI

### 5. Stop n8n

Press **Ctrl+C** in the terminal where n8n is running.

---

## Environment Variables

You can configure n8n by setting environment variables before starting it.

| Variable                 | Description                        | Default      |
| ------------------------ | ---------------------------------- | ------------ |
| `N8N_PORT`               | Port for the web UI                | `5678`       |
| `N8N_ENCRYPTION_KEY`     | Key used to encrypt credentials    | (auto-generated) |
| `N8N_DATABASE_TYPE`      | Database backend (sqlite / postgres) | `sqlite`   |
| `N8N_PAYLOAD_SIZE_MAX`   | Max payload size in MB             | `16`         |
| `N8N_METRICS`            | Enable Prometheus metrics          | `false`      |

Example with custom port:

```bash
N8N_PORT=5679 n8n start
```

---

## Exporting Workflows

To export a workflow from the n8n UI:

1. Open the workflow you want to export.
2. Click the **three dots** (⋯) menu in the top-right corner.
3. Select **Download** to save the workflow JSON.

Workflow exports can be placed in the `workflows/` directory for version
control and sharing.

---

## Directory Structure

```
n8n-workspace/
├── credentials/           # Store credential exports here
│   └── (empty)
├── workflows/             # Store workflow exports here
│   └── hello-world.json   # Starter workflow (Manual → Code → Respond)
├── start-n8n.sh           # Convenience launcher script
├── README.md              # This file
└── .gitignore             # Git ignore rules
```

Notes:

- **credentials/** — Place exported credential JSON files here to keep them
  under version control alongside your workflows.
- **workflows/** — JSON exports of your n8n workflows. The starter workflow is
  included by default.
- **start-n8n.sh** — A simple wrapper that prints info and starts n8n.
- **.gitignore** — Prevents committing database files, `node_modules/`, `.env`
  files, and OS junk.

---

## Troubleshooting

| Problem                          | Likely Fix                                         |
| -------------------------------- | -------------------------------------------------- |
| Port 5678 already in use         | Set `N8N_PORT=5679` or stop the other process      |
| n8n command not found            | Run `./setup-n8n.sh` to install or check `$PATH`   |
| Workflow won't import            | Ensure the JSON is valid and matches n8n 2.x format |
| Credentials not working          | Make sure `N8N_ENCRYPTION_KEY` is consistent       |

For more help, visit the [n8n documentation](https://docs.n8n.io).
EOF

# --- .gitignore ---
write_file "$WORKSPACE_DIR/.gitignore" << 'EOF'
# Database
*.db
*.sqlite

# Node modules (if local install is used)
node_modules/

# Environment files
.env

# OS files
.DS_Store
Thumbs.db

# n8n user data
.n8n/
EOF

# --- workflows/hello-world.json ---
write_file "$WORKFLOWS_DIR/hello-world.json" << 'EOF'
{
  "name": "Hello World",
  "nodes": [
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "name": "Manual Trigger",
      "type": "n8n-nodes-base.manualTrigger",
      "typeVersion": 1,
      "position": [250, 300],
      "parameters": {}
    },
    {
      "id": "00000000-0000-0000-0000-000000000002",
      "name": "Build Greeting",
      "type": "n8n-nodes-base.code",
      "typeVersion": 1,
      "position": [500, 300],
      "parameters": {
        "language": "javaScript",
        "code": "const output = {\n  greet: 'Hello from n8n!',\n  timestamp: new Date().toISOString(),\n  message: 'Your first n8n workflow is working!'\n};\nreturn [output];"
      }
    },
    {
      "id": "00000000-0000-0000-0000-000000000003",
      "name": "Done",
      "type": "n8n-nodes-base.noOp",
      "typeVersion": 1,
      "position": [750, 300],
      "parameters": {}
    }
  ],
  "connections": {
    "Manual Trigger": {
      "main": [
        [
          {
            "node": "Build Greeting",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Build Greeting": {
      "main": [
        [
          {
            "node": "Done",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  },
  "pinData": {},
  "versionId": "v1-init",
  "active": false,
  "settings": {},
  "staticData": null,
  "tags": []
}
EOF

echo ''

# ---------------------------------------------------------------------------
# Post-install instructions
# ---------------------------------------------------------------------------
banner '╔══════════════════════════════════════════════════════════════╗'
banner '║              Setup Complete                                 ║'
banner '╚══════════════════════════════════════════════════════════════╝'
echo ''
info "n8n ${n8n_version} is installed."
info "Workspace ready at: ${WORKSPACE_DIR}"
echo ''
echo -e "  ${C_BOLD}Next steps:${C_RESET}"
echo ''
echo -e "  1. ${C_GREEN}Start n8n:${C_RESET}     ${C_CYAN}${WORKSPACE_DIR}/start-n8n.sh${C_RESET}"
echo -e "     or:              ${C_CYAN}n8n start${C_RESET}"
echo ''
echo -e "  2. ${C_GREEN}Open n8n:${C_RESET}      ${C_CYAN}http://localhost:5678${C_RESET}"
echo ''
echo -e "  3. ${C_GREEN}Create account:${C_RESET} Follow the first-time setup wizard"
echo ''
echo -e "  4. ${C_GREEN}Import workflow:${C_RESET} Drag ${C_CYAN}workflows/hello-world.json${C_RESET}"
echo -e "     into the n8n UI"
echo ''
echo -e "  5. ${C_GREEN}Stop n8n:${C_RESET}       Press ${C_CYAN}Ctrl+C${C_RESET}"
echo ''
