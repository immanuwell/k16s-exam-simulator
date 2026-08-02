#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "desktop (noVNC web desktop)"

already_done "desktop" && { log_skip "desktop"; exit 0; }

apt_install tigervnc-standalone-server tigervnc-common openbox xterm novnc websockify x11-xserver-utils

source /etc/os-release
case "${ID}" in
  debian)
    # Chromium's current trixie build (151.0.7922.71-1~deb13u1) crashes on
    # launch under --no-sandbox: chrome_crashpad_handler exits immediately
    # ("--database is required"), which cascades into a fatal CHECK() and an
    # int3 trap in the browser process itself — reproduced directly, not an
    # environment issue (confirmed no seccomp/AppArmor denial in dmesg).
    # firefox-esr is a real .deb on Debian and launches cleanly.
    apt_install firefox-esr
    BROWSER_BIN="/usr/bin/firefox-esr"
    ;;
  ubuntu)
    # Ubuntu ships neither chromium nor firefox-esr as real apt packages
    # (both are transitional snap-installers) — snapd is preinstalled on
    # Ubuntu server images, so install Firefox straight from snap instead.
    if ! cmd_exists firefox; then
      log_info "Installing Firefox via snap (no usable apt package on Ubuntu)..."
      snap install firefox
    fi
    BROWSER_BIN="/snap/bin/firefox"
    ;;
  *)
    die "Unsupported OS '${ID}' for desktop step"
    ;;
esac
log_ok "Browser: ${BROWSER_BIN}"

# ── Candidate desktop config ───────────────────────────────────────────────
# No panel/taskbar is started — the real exam UI shows no window-manager
# chrome at all, just the split-pane webpage. Openbox's right-click menu is
# the only way in, matching "nothing visible until you launch something".

install -d -o candidate -g candidate -m 700 /home/candidate/.config/openbox

cat > /home/candidate/.config/openbox/autostart <<'EOF'
xsetroot -solid "#161922" &
xterm -fa Monospace -fs 12 -bg "#0d0f16" -fg "#d8dee9" &
EOF
chown candidate:candidate /home/candidate/.config/openbox/autostart
chmod +x /home/candidate/.config/openbox/autostart

cat > /home/candidate/.config/openbox/menu.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="K16S">
    <item label="Terminal">
      <action name="Execute"><command>xterm -fa Monospace -fs 12 -bg "#0d0f16" -fg "#d8dee9"</command></action>
    </item>
    <item label="Browser">
      <action name="Execute"><command>${BROWSER_BIN}</command></action>
    </item>
  </menu>
</openbox_menu>
EOF
chown candidate:candidate /home/candidate/.config/openbox/menu.xml

cat > /home/candidate/.config/openbox/rc.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <theme>
    <name>Clearlooks</name>
    <titleLayout>L</titleLayout>
    <keepBorder>no</keepBorder>
    <animationIconify>no</animationIconify>
  </theme>
  <desktops>
    <number>1</number>
    <popupTime>0</popupTime>
  </desktops>
  <keyboard>
    <keybind key="W-Return">
      <action name="Execute"><command>xterm -fa Monospace -fs 12 -bg "#0d0f16" -fg "#d8dee9"</command></action>
    </keybind>
    <keybind key="W-b">
      <action name="Execute"><command>__BROWSER_BIN__</command></action>
    </keybind>
  </keyboard>
</openbox_config>
EOF
sed -i "s|__BROWSER_BIN__|${BROWSER_BIN}|" /home/candidate/.config/openbox/rc.xml
chown candidate:candidate /home/candidate/.config/openbox/rc.xml

# ── Startup script: Xvnc (X server + VNC in one) → openbox → websockify ────

cat > /usr/local/bin/k16s-desktop-start <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

Xvnc :1 \
  -geometry 1280x800 \
  -depth 24 \
  -rfbport 5901 \
  -interface 127.0.0.1 \
  -SecurityTypes None \
  -AlwaysShared \
  -desktop k16s &
XVNC_PID=$!

for _ in $(seq 1 30); do
  [[ -S /tmp/.X11-unix/X1 ]] && break
  sleep 0.5
done
[[ -S /tmp/.X11-unix/X1 ]] || { echo "Xvnc did not start" >&2; exit 1; }

DISPLAY=:1 openbox-session &
OPENBOX_PID=$!

cleanup() { kill "${OPENBOX_PID}" "${XVNC_PID}" 2>/dev/null || true; }
trap cleanup EXIT

exec websockify --web=/usr/share/novnc 127.0.0.1:6080 127.0.0.1:5901
EOF
chmod +x /usr/local/bin/k16s-desktop-start
log_ok "k16s-desktop-start installed at /usr/local/bin/k16s-desktop-start"

cat > /etc/systemd/system/k16s-desktop.service <<'EOF'
[Unit]
Description=K16S Web Desktop (Xvnc + openbox + noVNC)
After=network.target

[Service]
Type=simple
User=candidate
Environment=HOME=/home/candidate
Environment=DISPLAY=:1
ExecStart=/usr/local/bin/k16s-desktop-start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now k16s-desktop.service
log_ok "k16s-desktop service started (Xvnc :1, websockify on 127.0.0.1:6080)"

mark_done "desktop"
