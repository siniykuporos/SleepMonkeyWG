#!/bin/bash
# =============================================================================
# setup-wireguard.sh
# Automated WireGuard + SwiftBar setup for macOS (multi-user)
# Supports Apple Silicon (M1/M2/M3) and Intel
#
# Admin user:   runs all 9 steps
# Regular user: runs only steps 8-9 (tray plugin + autostart)
# =============================================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Logging ---
step()    { echo ""; echo -e "${BOLD}${CYAN}▶ $*${NC}"; }
log_ok()  { echo -e "  ${GREEN}✓${NC}  $*"; }
log_warn(){ echo -e "  ${YELLOW}⚠${NC}  $*"; }
log_err() { echo -e "  ${RED}✗${NC}  $*"; }
log_info(){ echo -e "  ${CYAN}→${NC}  $*"; }

# =============================================================================
# DETECT USER TYPE
# =============================================================================

IS_ADMIN=false
if groups "$(whoami)" | grep -qw admin; then
    IS_ADMIN=true
fi

# =============================================================================
# WELCOME
# =============================================================================

clear
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║     WireGuard + SwiftBar — Automated Setup       ║"
echo "  ║     macOS multi-user VPN configuration           ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

if $IS_ADMIN; then
    echo -e "  Detected: ${GREEN}admin user${NC} — full setup (steps 1–9)"
    echo ""
    echo -e "  This script will:"
    echo -e "  ${CYAN}1.${NC} Install Homebrew (if needed)"
    echo -e "  ${CYAN}2.${NC} Install wireguard-tools"
    echo -e "  ${CYAN}3.${NC} Install SwiftBar"
    echo -e "  ${CYAN}4.${NC} Copy your WireGuard config to /etc/wireguard/"
    echo -e "  ${CYAN}5.${NC} Create a bash wrapper (fixes macOS bash 3 issue)"
    echo -e "  ${CYAN}6.${NC} Register WireGuard as a system-level launchd daemon"
    echo -e "  ${CYAN}7.${NC} Configure sudoers (passwordless VPN control for all users)"
    echo -e "  ${CYAN}8.${NC} Install SwiftBar tray plugin"
    echo -e "  ${CYAN}9.${NC} Configure SwiftBar to auto-start on login"
else
    echo -e "  Detected: ${YELLOW}regular user${NC} — installing tray plugin only (steps 8–9)"
    echo ""
    echo -e "  This script will:"
    echo -e "  ${CYAN}8.${NC} Install SwiftBar tray plugin"
    echo -e "  ${CYAN}9.${NC} Configure SwiftBar to auto-start on login"
    echo ""
    echo -e "  ${YELLOW}Steps 1–7 require an admin user and should already be done.${NC}"
fi

echo ""
read -rp "  Press Enter to continue or Ctrl+C to cancel..."

# =============================================================================
# 0. PREFLIGHT CHECKS
# =============================================================================

step "Preflight checks"

if [[ "$(uname)" != "Darwin" ]]; then
    log_err "This script is for macOS only."
    exit 1
fi
log_ok "macOS $(sw_vers -productVersion)"
log_ok "Running as: $(whoami)"

ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    BREW_PREFIX="/opt/homebrew"
    log_ok "Architecture: Apple Silicon (arm64)"
else
    BREW_PREFIX="/usr/local"
    log_ok "Architecture: Intel (x86_64)"
fi

BREW="$BREW_PREFIX/bin/brew"
WG_BIN="$BREW_PREFIX/bin/wg"
WG_QUICK="$BREW_PREFIX/bin/wg-quick"
HOMEBREW_BASH="$BREW_PREFIX/bin/bash"

if $IS_ADMIN; then
    log_info "Requesting admin privileges (sudo)..."
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_PID=$!
    trap 'kill $SUDO_PID 2>/dev/null; echo ""' EXIT
else
    # Verify that system-level setup is already done
    if [[ ! -f "/Library/LaunchDaemons/com.wireguard.wg0.plist" ]]; then
        log_err "System daemon not found. An admin user must run this script first."
        exit 1
    fi
    if [[ ! -f "/etc/sudoers.d/wireguard" ]]; then
        log_err "sudoers not configured. An admin user must run this script first."
        exit 1
    fi
    if [[ ! -d "/Applications/SwiftBar.app" ]]; then
        log_err "SwiftBar not installed. An admin user must run this script first."
        exit 1
    fi
    log_ok "System-level setup already done by admin."
fi

# =============================================================================
# ADMIN-ONLY STEPS (1–7)
# =============================================================================

if $IS_ADMIN; then

# ---------------------------------------------------------------------------
step "Step 1/9 — Homebrew"

if [[ -f "$BREW" ]]; then
    log_ok "Homebrew already installed: $($BREW --version | head -1)"
else
    log_info "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    log_ok "Homebrew installed successfully."
fi

# ---------------------------------------------------------------------------
step "Step 2/9 — wireguard-tools"
log_info "Installing wireguard-tools (wg, wg-quick)..."

if [[ -f "$WG_BIN" ]]; then
    log_ok "wireguard-tools already installed: $WG_BIN"
else
    "$BREW" install wireguard-tools
    log_ok "wireguard-tools installed."
fi

if [[ ! -f "$HOMEBREW_BASH" ]]; then
    log_info "Installing bash 5+ (required by wg-quick on macOS)..."
    "$BREW" install bash
    log_ok "bash installed: $HOMEBREW_BASH"
else
    log_ok "bash 5+ already available: $HOMEBREW_BASH"
fi

# ---------------------------------------------------------------------------
step "Step 3/9 — SwiftBar"
log_info "Installing SwiftBar (menu bar app)..."

if [[ -d "/Applications/SwiftBar.app" ]]; then
    log_ok "SwiftBar already installed."
else
    "$BREW" install --cask swiftbar
    log_ok "SwiftBar installed."
fi

# ---------------------------------------------------------------------------
step "Step 4/9 — WireGuard config"

WG_CONF_DIR="/etc/wireguard"
WG_CONF="$WG_CONF_DIR/wg0.conf"
sudo mkdir -p "$WG_CONF_DIR"

if [[ -f "$WG_CONF" ]]; then
    log_ok "Config already exists: $WG_CONF"
else
    log_warn "No config found at $WG_CONF"
    echo ""
    echo -e "  ${YELLOW}Please provide the path to your WireGuard .conf file:${NC}"
    read -rp "  Path (leave empty to skip): " CONF_SRC

    if [[ -n "$CONF_SRC" && -f "$CONF_SRC" ]]; then
        sudo cp "$CONF_SRC" "$WG_CONF"
        sudo chmod 600 "$WG_CONF"
        sudo chown root:wheel "$WG_CONF"
        log_ok "Config copied to $WG_CONF"
    else
        log_warn "Skipped. Place your config at $WG_CONF then run:"
        log_warn "sudo launchctl start com.wireguard.wg0"
    fi
fi

# ---------------------------------------------------------------------------
step "Step 5/9 — bash wrapper for wg-quick"
log_info "macOS ships with bash 3.2 — wg-quick requires bash 4+."
log_info "Creating a wrapper that explicitly calls Homebrew bash..."

WRAPPER_UP="/usr/local/bin/wg-quick-up.sh"

sudo tee "$WRAPPER_UP" > /dev/null << WRAPPER
#!/bin/bash
exec $HOMEBREW_BASH $WG_QUICK up wg0
WRAPPER

sudo chmod +x "$WRAPPER_UP"
log_ok "Wrapper created: $WRAPPER_UP"

# ---------------------------------------------------------------------------
step "Step 6/9 — launchd system daemon"
log_info "Registering WireGuard as a system-level service."
log_info "This daemon runs for ALL users regardless of who is logged in."
log_info "This solves the multi-user conflict with the WireGuard GUI app."

PLIST="/Library/LaunchDaemons/com.wireguard.wg0.plist"

sudo tee "$PLIST" > /dev/null << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.wireguard.wg0</string>
    <key>ProgramArguments</key>
    <array>
        <string>$WRAPPER_UP</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/var/log/wireguard.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/wireguard.err</string>
</dict>
</plist>
PLIST

sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"

if sudo launchctl list | grep -q "com.wireguard.wg0"; then
    log_info "Daemon already registered — reloading..."
    sudo launchctl unload "$PLIST" 2>/dev/null || true
fi

sudo launchctl load "$PLIST"
log_ok "Daemon registered: com.wireguard.wg0"

if [[ -f "${WG_CONF:-}" ]]; then
    log_info "Starting tunnel..."
    sudo launchctl start com.wireguard.wg0
    sleep 2
    if sudo "$WG_BIN" show &>/dev/null; then
        log_ok "Tunnel is up!"
    else
        log_warn "Tunnel did not start. Check: cat /var/log/wireguard.err"
    fi
fi

# ---------------------------------------------------------------------------
step "Step 7/9 — sudoers (passwordless VPN control)"
log_info "Granting all users (staff group) the ability to start/stop VPN without a password."
log_info "Only these three specific commands are allowed — nothing else."

SUDOERS_FILE="/etc/sudoers.d/wireguard"

sudo tee "$SUDOERS_FILE" > /dev/null << SUDOERS
# WireGuard — passwordless control for all users (staff group)
%staff ALL=(ALL) NOPASSWD: /bin/launchctl start com.wireguard.wg0
%staff ALL=(ALL) NOPASSWD: /bin/launchctl stop com.wireguard.wg0
%staff ALL=(ALL) NOPASSWD: $WG_BIN show
SUDOERS

sudo chmod 440 "$SUDOERS_FILE"
sudo chown root:wheel "$SUDOERS_FILE"

if sudo visudo -c -f "$SUDOERS_FILE" &>/dev/null; then
    log_ok "sudoers configured: $SUDOERS_FILE"
else
    log_err "sudoers syntax error! Removing file to prevent lockout."
    sudo rm -f "$SUDOERS_FILE"
    exit 1
fi

fi # end IS_ADMIN

# =============================================================================
# STEPS 8–9 (all users)
# =============================================================================

# ---------------------------------------------------------------------------
step "Step 8/9 — SwiftBar tray plugin"
log_info "Installing menu bar plugin for $(whoami)."
log_info "Shows VPN status (🙈 connected / 🐵 disconnected),"
log_info "current IP from 2ip.ru and 2ip.io, and connect/disconnect buttons."
log_info "Status refreshes every 5 seconds. IP refreshes every 60 seconds."

PLUGINS_DIR="$HOME/.swiftbar"
PREFS_DIR=$(defaults read com.ameba.SwiftBar PluginsDirectory 2>/dev/null || true)
if [[ -n "$PREFS_DIR" && -d "$PREFS_DIR" ]]; then
    PLUGINS_DIR="$PREFS_DIR"
fi
mkdir -p "$PLUGINS_DIR"

PLUGIN="$PLUGINS_DIR/wireguard.5s.sh"

cat > "$PLUGIN" << 'PLUGIN'
#!/bin/bash
# Detect wg path (Apple Silicon vs Intel)
WG=$( [[ -f /opt/homebrew/bin/wg ]] && echo "/opt/homebrew/bin/wg" || echo "/usr/local/bin/wg" )

WG_OUT=$(/usr/bin/sudo "$WG" show 2>/dev/null)

IP_CACHE1="/tmp/swiftbar_ip1"
IP_CACHE2="/tmp/swiftbar_ip2"

if [ ! -f "$IP_CACHE1" ] || [ $(( $(date +%s) - $(stat -f %m "$IP_CACHE1") )) -gt 60 ]; then
    /usr/bin/curl -s --max-time 3 https://2ip.ru | tr -d '[:space:]' > "$IP_CACHE1"
fi
if [ ! -f "$IP_CACHE2" ] || [ $(( $(date +%s) - $(stat -f %m "$IP_CACHE2") )) -gt 60 ]; then
    /usr/bin/curl -s --max-time 3 https://2ip.io | tr -d '[:space:]' > "$IP_CACHE2"
fi

IP1=$(cat "$IP_CACHE1" 2>/dev/null || echo "n/a")
IP2=$(cat "$IP_CACHE2" 2>/dev/null || echo "n/a")

if [ -n "$WG_OUT" ]; then
    echo "🙈"
    echo "---"
    echo "2ip.ru: $IP1"
    echo "2ip.io: $IP2"
    echo "---"
    echo "🟢 Connected"
    echo "---"
    echo "🔴 Disconnect | bash=/usr/bin/sudo param1=/bin/launchctl param2=stop param3=com.wireguard.wg0 terminal=false refresh=true"
else
    echo "🐵"
    echo "---"
    echo "2ip.ru: $IP1"
    echo "2ip.io: $IP2"
    echo "---"
    echo "🔴 Disconnected"
    echo "---"
    echo "🟢 Connect | bash=/usr/bin/sudo param1=/bin/launchctl param2=start param3=com.wireguard.wg0 terminal=false refresh=true"
fi
PLUGIN

chmod +x "$PLUGIN"
defaults write com.ameba.SwiftBar PluginsDirectory "$PLUGINS_DIR"
log_ok "Plugin installed: $PLUGIN"

# ---------------------------------------------------------------------------
step "Step 9/9 — SwiftBar auto-start on login"
log_info "Configuring SwiftBar to launch automatically when $(whoami) logs in."

LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.ameba.SwiftBar.plist"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$LAUNCH_AGENT" << AGENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ameba.SwiftBar</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/SwiftBar.app/Contents/MacOS/SwiftBar</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>SWIFTBAR_PLUGINS_PATH</key>
        <string>$PLUGINS_DIR</string>
    </dict>
</dict>
</plist>
AGENT

launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT"
log_ok "SwiftBar auto-start configured."

log_info "Restarting SwiftBar..."
pkill -u "$(whoami)" SwiftBar 2>/dev/null || true
sleep 1
SWIFTBAR_PLUGINS_PATH="$PLUGINS_DIR" open -a SwiftBar 2>/dev/null || log_warn "Could not launch SwiftBar — open it manually from /Applications."
log_ok "SwiftBar restarted."

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║              Setup complete! 🎉                  ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

if $IS_ADMIN; then
    echo -e "  ${BOLD}VPN control:${NC}"
    echo -e "  ${CYAN}Start:${NC}   sudo launchctl start com.wireguard.wg0"
    echo -e "  ${CYAN}Stop:${NC}    sudo launchctl stop com.wireguard.wg0"
    echo -e "  ${CYAN}Status:${NC}  sudo $WG_BIN show"
    echo -e "  ${CYAN}Logs:${NC}    tail -f /var/log/wireguard.err"
    echo ""
fi

echo -e "  ${BOLD}SwiftBar plugin:${NC} $PLUGIN"
echo ""
echo -e "  ${BOLD}For other users on this Mac:${NC}"
echo -e "  Each user runs this script once — steps 1–7 will"
echo -e "  be skipped automatically, only 8–9 will run."
echo ""
