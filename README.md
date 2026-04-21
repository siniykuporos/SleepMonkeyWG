# WireGuard + SwiftBar for macOS

Automated setup of WireGuard as a **system-level service** with a SwiftBar tray plugin for multi-user macOS machines.

## The Problem

The WireGuard GUI app from the App Store runs in the context of a specific user. When that user locks their session, the tunnel stays active and **blocks other users** from starting their own WireGuard instance.

## The Solution

WireGuard is moved out of user space into a **launchd system daemon** — it runs at the OS level, independent of who is logged in. Each user gets their own SwiftBar tray icon to control the shared tunnel.

```
┌─────────────────────────────────────────┐
│           launchd system daemon         │  ← runs as root, always available
│         com.wireguard.wg0               │
└────────────────┬────────────────────────┘
                 │
       ┌─────────┴──────────┐
       │                    │
  ┌────▼────┐          ┌────▼────┐
  │ User 1  │          │ User 2  │
  │SwiftBar │          │SwiftBar │   ← each user has their own tray icon
  └─────────┘          └─────────┘
```

## Requirements

- macOS 12+
- Apple Silicon (M1/M2/M3) or Intel
- Admin user for initial setup
- A WireGuard `.conf` file

## Files

| File | Description |
|------|-------------|
| `setup-wireguard.sh` | Automated setup script |
| `wireguard.5s.sh` | SwiftBar tray plugin (standalone) |

## Quick Start

### Admin user (first time)

```bash
bash setup-wireguard.sh
```

The script will:

1. Install Homebrew (if needed)
2. Install `wireguard-tools` and `bash 5+`
3. Install SwiftBar
4. Copy your `.conf` to `/etc/wireguard/wg0.conf`
5. Create a bash wrapper (fixes macOS bash 3.2 compatibility issue)
6. Register WireGuard as a `launchd` system daemon
7. Configure `sudoers` — passwordless VPN control for all users
8. Install SwiftBar tray plugin
9. Configure SwiftBar to auto-start on login

### Regular user (subsequent users)

```bash
bash setup-wireguard.sh
```

The script auto-detects non-admin users and skips steps 1–7, running only steps 8–9 (tray plugin + autostart).

> **Note:** An admin must run the script first before regular users can set it up.

## Tray Plugin

The SwiftBar plugin updates every 5 seconds and shows:

```
🙈                        ← VPN connected
─────────────────
2ip.ru: 185.x.x.x
2ip.io: 185.x.x.x
─────────────────
🟢 Connected
─────────────────
🔴 Disconnect
```

```
🐵                        ← VPN disconnected
─────────────────
2ip.ru: 95.x.x.x
2ip.io: 95.x.x.x
─────────────────
🔴 Disconnected
─────────────────
🟢 Connect
```

IP addresses are cached and refreshed every 60 seconds.

## Manual VPN Control

```bash
# Start
sudo launchctl start com.wireguard.wg0

# Stop
sudo launchctl stop com.wireguard.wg0

# Status
sudo wg show

# Logs
tail -f /var/log/wireguard.err
```

## Files Created by the Script

| Path | Description |
|------|-------------|
| `/etc/wireguard/wg0.conf` | WireGuard config |
| `/usr/local/bin/wg-quick-up.sh` | bash wrapper for wg-quick |
| `/Library/LaunchDaemons/com.wireguard.wg0.plist` | launchd system daemon |
| `/etc/sudoers.d/wireguard` | sudoers rules |
| `~/.swiftbar/wireguard.5s.sh` | SwiftBar plugin (per user) |
| `~/Library/LaunchAgents/com.ameba.SwiftBar.plist` | SwiftBar autostart (per user) |

## Why a bash Wrapper?

macOS ships with bash 3.2 (due to GPL licensing). `wg-quick` requires bash 4+. Homebrew installs bash 5+ at `/opt/homebrew/bin/bash`, but `launchd` uses the system shell. The wrapper script explicitly calls the Homebrew bash.

## Sudoers

The script grants passwordless access to exactly three commands for the `staff` group (all macOS users):

```
%staff ALL=(ALL) NOPASSWD: /bin/launchctl start com.wireguard.wg0
%staff ALL=(ALL) NOPASSWD: /bin/launchctl stop com.wireguard.wg0
%staff ALL=(ALL) NOPASSWD: /opt/homebrew/bin/wg show
```

## Compatibility

| | Apple Silicon | Intel |
|---|---|---|
| Homebrew prefix | `/opt/homebrew` | `/usr/local` |
| `wg` path | `/opt/homebrew/bin/wg` | `/usr/local/bin/wg` |
| `bash` path | `/opt/homebrew/bin/bash` | `/usr/local/bin/bash` |

The setup script and plugin detect the architecture automatically.
