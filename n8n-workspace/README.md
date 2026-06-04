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
- **Done** — a NoOp node (pass-through, completing the chain)

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

## License Activation

If you have an n8n license key, you can activate it through the UI:

1. Open **Settings → Usage & Plan** in the n8n web UI
2. Click **Enter License Key** and paste your key

### Node.js 26 Workaround

On **Node.js 26+**, the built-in license activation may fail with:

```
[license SDK] license activation failed: Connection Error: fetch failed
```

This is a known compatibility issue between the `@n8n_io/license-sdk` bundled
`undici` version and Node.js 26. If this happens, use the fix script from the
repo root:

```bash
cd ..
./fix-license-activation.sh <YOUR_LICENSE_KEY> --email your@email.com
```

The script will prompt for your password, then handle the activation externally
and inject the certificate directly into n8n's database.

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
│   └── hello-world.json   # Starter workflow (Manual → Code → Done)
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
| License activation fails         | Run `../fix-license-activation.sh <KEY> --email your@email.com` |

For more help, visit the [n8n documentation](https://docs.n8n.io).
