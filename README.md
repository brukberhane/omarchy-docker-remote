# Docker Remote for Omarchy

Monitor and control Docker containers and Compose stacks on a **remote host over SSH** from the Omarchy bar.

Inspired by [OmiDocker](https://github.com/Erruviel/omarchy-docker) (local) and wired like [Proxmarchy](https://github.com/boyoyooo/proxmarchy) (remote host + bar panel).

## Features

- **Compose stacks** grouped by `com.docker.compose.project`
- **Per-container** start, stop, restart, unpause, remove (confirm)
- **Stack** start (`compose up -d`) / stop (`docker stop`, never `down`)
- **Logs and shell** in a floating terminal over SSH
- **CPU/memory** while the panel is open
- **Host stats** — remote CPU, RAM, and root disk (Proxmarchy-style card)
- **Port links** open via `xdg-open` (`http://` or `https://` from port base URL)
- **Health** badges, bar alert dot, desktop notify on unhealthy flip
- **Setup in the panel** when no host is configured yet

## Requirements

On the **Omarchy machine**:

- `docker` CLI (client only — talks to the remote daemon over SSH)
- `jq`, `ssh`

On the **remote host**:

- Docker daemon running
- SSH key login (BatchMode — no password prompts from the bar)
- Your SSH user in the `docker` group:

  ```bash
  sudo usermod -aG docker "$USER"
  ```

## Install

```bash
omarchy plugin add /home/brukb/.config/omarchy/plugins/io.github.brukb.docker-remote --enable
```

Or from Git once published:

```bash
omarchy plugin add https://github.com/brukb/omarchy-docker-remote.git --enable
```

Add to `~/.config/omarchy/shell.json` bar layout (left section, next to Proxmarchy):

```json
{
  "id": "io.github.brukb.docker-remote",
  "interval": 15,
  "showCount": true,
  "notifyUnhealthy": true,
  "terminal": "xdg-terminal-exec"
}
```

Click the whale → fill **Host**, **SSH user**, optional **Label** and **Port base URL** → **Save and connect**.

Settings can also live in `shell.json` (`host`, `sshUser`, `label`, `portBaseUrl`, `sshIdentityFile`) or in:

`~/.config/omarchy/docker-remote/default.conf`

(`shell.json` wins when both are set.)

## Settings

| Key | Default | Meaning |
|-----|---------|---------|
| `host` | — | Remote IP, hostname, or SSH config alias |
| `sshUser` | — | SSH user on the remote host |
| `label` | host | Bar/panel title |
| `portBaseUrl` | `http://<host>` | Prefix for port link clicks |
| `sshIdentityFile` | — | Optional private key path |
| `interval` | `15` | Poll seconds while panel closed |
| `showCount` | `true` | `running/total` on the bar |
| `notifyUnhealthy` | `true` | Desktop notification on unhealthy |
| `terminal` | `xdg-terminal-exec` | Terminal for logs/shell |

## Uninstall

```bash
omarchy plugin remove io.github.brukb.docker-remote
```

## License

MIT — see [LICENSE](LICENSE).
