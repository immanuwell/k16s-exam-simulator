#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "desktop (noVNC web desktop)"

already_done "desktop" && { log_skip "desktop"; exit 0; }

apt_install tigervnc-standalone-server tigervnc-common openbox tint2 xterm novnc websockify x11-xserver-utils

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
    BROWSER_ICON="/usr/share/icons/hicolor/48x48/apps/firefox-esr.png"
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
    # Best-effort: relies on the "firefox" icon name resolving via the snap's
    # desktop-icon integration (/var/lib/snapd/desktop/icons) — not verified
    # on Ubuntu the way the Debian path above was.
    BROWSER_ICON="firefox"
    ;;
  *)
    die "Unsupported OS '${ID}' for desktop step"
    ;;
esac
log_ok "Browser: ${BROWSER_BIN}"

# ── Candidate desktop config ───────────────────────────────────────────────
# tint2 gives a launcher (Terminal/Browser icons) and a taskbar (click to
# switch windows) — a real WM chrome the exam itself never shows, but without
# it there's no discoverable way to open a second window or switch back to
# one that's covered. Still a small fraction of xfce's panel+compositor cost.

install -d -o candidate -g candidate -m 700 /home/candidate/.config/openbox
install -d -o candidate -g candidate -m 700 /home/candidate/.config/tint2

cat > /usr/share/applications/k16s-terminal.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Terminal
Exec=xterm -fa Monospace -fs 12 -bg "#0d0f16" -fg "#d8dee9"
Icon=/usr/share/pixmaps/xterm-color_48x48.xpm
Categories=System;
EOF

cat > /usr/share/applications/k16s-browser.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Browser
Exec=${BROWSER_BIN}
Icon=${BROWSER_ICON}
Categories=Network;
EOF

cat > /home/candidate/.config/tint2/tint2rc <<'EOF'
#-------------------------------------
# Backgrounds
# Background 1: Panel
rounded = 0
border_width = 0
border_sides = TBLR
background_color = #161922 100
border_color = #2a2f42 100
background_color_hover = #161922 100
border_color_hover = #2a2f42 100
background_color_pressed = #161922 100
border_color_pressed = #2a2f42 100

# Background 2: Default task
rounded = 3
border_width = 0
border_sides = TBLR
background_color = #2a2f42 100
border_color = #2a2f42 100
background_color_hover = #353b52 100
border_color_hover = #353b52 100
background_color_pressed = #353b52 100
border_color_pressed = #353b52 100

# Background 3: Active task
rounded = 3
border_width = 0
border_sides = TBLR
background_color = #3b82f6 100
border_color = #3b82f6 100
background_color_hover = #3b82f6 100
border_color_hover = #3b82f6 100
background_color_pressed = #2563eb 100
border_color_pressed = #2563eb 100

#-------------------------------------
# Panel
panel_items = LT
panel_size = 100% 34
panel_margin = 0 0
panel_padding = 6 3 6
panel_background_id = 1
panel_layer = top
panel_position = bottom center horizontal
panel_dock = 0
strut_policy = follow_size
panel_monitor = all
wm_menu = 0

#-------------------------------------
# Launcher
launcher_padding = 0 0 6
launcher_background_id = 0
launcher_icon_background_id = 0
launcher_icon_size = 22
launcher_icon_theme_override = 0
launcher_tooltip = 1
launcher_item_app = /usr/share/applications/k16s-terminal.desktop
launcher_item_app = /usr/share/applications/k16s-browser.desktop

#-------------------------------------
# Taskbar
taskbar_mode = single_desktop
taskbar_padding = 4 0
taskbar_background_id = 0
taskbar_active_background_id = 0
taskbar_name = 0
taskbar_hide_inactive_tasks = 0
taskbar_distribute_size = 0
taskbar_sort_order = none
task_align = left

#-------------------------------------
# Task
task_icon = 1
task_text = 1
task_centered = 1
task_maximum_size = 200 30
task_padding = 6 3
task_font = sans 9
task_tooltip = 1
task_background_id = 2
task_active_background_id = 3
task_font_color = #d8dee9 100
task_active_font_color = #ffffff 100
mouse_left = toggle_iconify
mouse_middle = none
mouse_right = close
mouse_scroll_up = none
mouse_scroll_down = none
EOF
chown -R candidate:candidate /home/candidate/.config/tint2

cat > /home/candidate/.config/openbox/autostart <<'EOF'
xsetroot -solid "#161922" &
tint2 &
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
