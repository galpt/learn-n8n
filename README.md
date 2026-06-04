# learn-n8n

A ready-to-use n8n workspace for learning workflow automation on Linux.

## Features

- **`setup-n8n.sh`** — Installs n8n on Arch-based Linux (via AUR) and creates a ready-to-use workspace
- **`fix-license-activation.sh`** — Workaround for the Node.js 26+ / undici license activation bug
- **`n8n-workspace/`** — Pre-configured workspace with starter workflow, launcher script, and docs

## Quick Start

```bash
# 1. Install n8n and set up the workspace
./setup-n8n.sh

# 2. Start n8n
cd n8n-workspace && ./start-n8n.sh

# 3. Open http://localhost:5678, create your owner account
# 4. Import workflows/workflows/hello-world.json
# 5. Click "Execute Workflow"
```

## The License Activation Problem

On **Node.js 26+**, n8n's internal HTTP client (`undici`) can fail to connect to the
license server (`license.n8n.io`) with:

```
[license SDK] license activation failed: Connection Error: fetch failed
```

Even though normal `curl` and `node` requests work fine. This is a compatibility
issue between the bundled `undici` version in n8n 2.23 and Node.js 26.

### Fix

```bash
./fix-license-activation.sh <YOUR_LICENSE_KEY> --email you@example.com
```

The script prompts for your password, then:

1. Gets your n8n instance ID (device fingerprint) from the API
2. Activates the license via a direct HTTPS call (bypassing n8n's broken fetch)
3. Injects the certificate into the n8n SQLite database
4. Tells you to restart n8n

See `fix-license-activation.sh --help` for all options.

## Directory Structure

```
learn-n8n/
├── LICENSE                    # MIT License
├── README.md                  # This file
├── setup-n8n.sh               # n8n installation script (Arch Linux)
├── fix-license-activation.sh  # License activation workaround
└── n8n-workspace/
    ├── start-n8n.sh           # Convenience launcher
    ├── README.md              # Workspace documentation
    ├── .gitignore
    ├── credentials/           # For credential exports
    └── workflows/
        └── hello-world.json   # Starter workflow (Manual → Code → Done)
```

## Requirements

- **OS**: Linux (Arch-based for `setup-n8n.sh`, others for manual install)
- **Node.js**: >= 18.10 (n8n requires this)
- **Runtime**: Node.js 18–22 recommended; Node.js 26 has the license activation bug

## License

MIT
