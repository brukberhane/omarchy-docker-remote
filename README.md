# Docker Remote for Omarchy

Monitor and control Docker containers and Compose stacks on **one or more remote hosts over SSH** from the [Omarchy](https://omarchy.org) bar.

Same panel UX as local [OmiDocker](https://github.com/Erruviel/omarchy-docker), with remote transport and multi-host tabs modeled after [Proxmarchy](https://github.com/boyoyooo/proxmarchy).

## Features

### Bar

- Whale icon with optional `running/total` count for the **active** host
- Alert styling when **any** configured host is unreachable or has unhealthy containers
- Red dot when the active host has unhealthy containers
- Middle-click refreshes; left-click opens the panel

### Multi-host panel

- **Tabs** per host — title is the **Label** you set, falling back to the host IP/hostname
- **+** adds another host (Host, SSH user, optional Label, port base URL, SSH key)
- **Trash** or **right-click tab** removes a host (with confirmation)
- Per-host poll cache; background refresh rotates through non-active hosts for tab alert dots
- First open shows a setup form when no hosts exist yet

### Containers & stacks

- **Compose stacks** grouped by `com.docker.compose.project`
- **Per-container** start, stop, restart, unpause, remove (confirm)
- **Stack** start (`docker compose up -d` when compose labels include a working dir) / stop (`docker stop` on stack containers — never `compose down`)
- **Logs** and **shell** in a detached terminal over SSH (`ssh -t … docker logs|exec`)
- **Port links** open via `xdg-open` — scheme comes from **Port base URL** (`http://` or `https://`, default `http://<host>`)
- **Health** badges; desktop notification when a container newly turns unhealthy (optional)

### Host metrics

- **Live container stats** (`docker stats --no-stream`) while the panel is open
- **Host stats card** — remote CPU, RAM, and root filesystem usage (Proxmarchy-style layout)

## Requirements

On the **Omarchy machine**:

- `docker` CLI (client only — commands run on the remote host over SSH)
- `jq`, OpenSSH `ssh`

On each **remote host**:

- Docker daemon running
- SSH key login (`BatchMode` — no password prompts from the bar)
- Your SSH user in the `docker` group:

  ```bash
  sudo usermod -aG docker "$USER"
  # log out/in on the remote host
  ssh -o BatchMode=yes user@remote docker ps
  ```

## Install

From a local clone:

```bash
omarchy plugin add /path/to/omarchy-docker-remote --enable
```

From Git (once published):

```bash
omarchy plugin add https://github.com/brukb/omarchy-docker-remote.git --enable
```

Add to `~/.config/omarchy/shell.json` (example: left bar, after Proxmarchy):

```json
{
  "id": "io.github.brukb.docker-remote",
  "interval": 15,
  "showCount": true,
  "notifyUnhealthy": true,
  "terminal": "xdg-terminal-exec"
}
```

If the widget does not appear after editing `shell.json`:

```bash
omarchy-shell shell rescanPlugins
```

Click the whale → fill **Host** and **SSH user** → optional **Label** (tab title) and **Port base URL** → **Save and connect**. Use **+** for additional hosts.

## Configuration

Host connection details are stored per widget instance in JSON (not in `shell.json`):

`~/.config/omarchy/docker-remote/<instanceId>.json`

The default instance uses `default.json`. Legacy `default.conf` is migrated automatically on first read.

Example store:

```json
{
  "activeId": "homelab",
  "hosts": [
    {
      "id": "homelab",
      "host": "192.168.1.10",
      "sshUser": "deploy",
      "label": "Homelab",
      "portBaseUrl": "http://192.168.1.10",
      "sshIdentityFile": ""
    }
  ]
}
```

CLI helper (same binary the widget uses):

```bash
PLUGIN=~/.config/omarchy/plugins/io.github.brukb.docker-remote

$PLUGIN/bin/docker-remote-config list default
$PLUGIN/bin/docker-remote-config add default host=192.168.1.11 sshUser=deploy label=Edge
$PLUGIN/bin/docker-remote-config set-active default Edge
$PLUGIN/bin/docker-remote-config update default Edge label=EdgeBox portBaseUrl=http://192.168.1.11
$PLUGIN/bin/docker-remote-config remove default Edge
```

### Widget settings (`shell.json`)

These apply to the bar widget instance only:

| Key | Default | Meaning |
|-----|---------|---------|
| `interval` | `15` | Poll interval in seconds (5–120); panel open polls every 10s |
| `showCount` | `true` | Show `running/total` on the bar icon |
| `notifyUnhealthy` | `true` | `notify-send` when a container turns unhealthy |
| `terminal` | `xdg-terminal-exec` | Terminal launcher for logs/shell SSH sessions |
| `instanceId` | `default` | Config file suffix (`<instanceId>.json`) when using multiple widget instances |

`allowMultiple: true` in the manifest — add several bar entries with different `instanceId` values for separate host lists.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Widget missing after install | `omarchy-shell shell rescanPlugins` |
| `SSH permission denied` | `ssh -o BatchMode=yes user@host true`; key in agent |
| Empty container list | OpenSSH stderr in poller (fixed in v0.1 — needs `LogLevel=ERROR`) |
| Port link does nothing | Links use `Quickshell.execDetached` + `xdg-open`, not shell strings |
| Tab shows IP not Label | Set **Label** on add, or `docker-remote-config update … label=…` |
| Label lost on Save | Fixed — form reads all fields on Save, not only on blur |

Test the poller manually:

```bash
~/.config/omarchy/plugins/io.github.brukb.docker-remote/bin/docker-remote-status HOST USER
```

## Acknowledgements

This plugin is an original work by [brukb](https://github.com/brukb). It was built for Omarchy and draws ideas and UI patterns from these projects — thank you to their authors:

| Project | Author | What we reused |
|---------|--------|----------------|
| [OmiDocker / omarchy-docker](https://github.com/Erruviel/omarchy-docker) | [Erruviel](https://github.com/Erruviel) | Compose stack grouping, container row actions, `BarIconButton` bar widget, stack start/stop semantics, health badges |
| [Proxmarchy](https://github.com/boyoyooo/proxmarchy) | [boyoyooo](https://github.com/boyoyooo) | Remote host panel layout, host stats card (CPU/RAM/disk), `PanelHero` / action button patterns, multi-target bar widget model |
| [omarchy-plugin-proxmox](https://github.com/g-desoutter/omarchy-plugin-proxmox) | [g-desoutter](https://github.com/g-desoutter) | Upstream read-only Proxmox bar widget that Proxmarchy extended |
| [Omarchy](https://omarchy.org) | DHH et al. | Quickshell shell, `qs.Ui` / `qs.Commons` components (`Panel`, `Button`, `BarIconButton`, etc.) |

No source code was copied verbatim from OmiDocker or Proxmarchy; transport is SSH-wrapped Docker CLI instead of a local socket or Proxmox API.

## Uninstall

```bash
omarchy plugin remove io.github.brukb.docker-remote
```

Optionally remove saved hosts:

```bash
rm -rf ~/.config/omarchy/docker-remote/
```

## License

MIT — see [LICENSE](LICENSE).
