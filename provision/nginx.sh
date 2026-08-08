#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "nginx (reverse proxy)"

already_done "nginx" && { log_skip "nginx"; exit 0; }

apt_install nginx

DESKTOP_ENABLED="${K16S_DESKTOP:-true}"
# Set by install.sh when the target IP is public — nginx then only accepts
# connections from the machine itself, and the only way in is the SSH tunnel
# install.sh opens automatically. Private/LAN targets are unaffected: those
# already aren't reachable from the public internet, so there's nothing to
# close off, and direct-IP access keeps working exactly as before.
BIND_LOOPBACK="${K16S_BIND_LOOPBACK:-false}"
if [[ "${BIND_LOOPBACK}" == "true" ]]; then
  BIND_V4="127.0.0.1"; BIND_V6="::1"
else
  BIND_V4="0.0.0.0"; BIND_V6="::"
fi

cat > /etc/nginx/sites-available/k16s <<'NGINXCONF'
map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}

server {
  listen __BIND_V4__:80 default_server;
  listen [__BIND_V6__]:80 default_server;
  server_name _;

  location / {
    proxy_pass         http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header   Host              $host;
    proxy_set_header   X-Real-IP         $remote_addr;
    proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header   Upgrade           $http_upgrade;
    proxy_set_header   Connection        $connection_upgrade;
    proxy_read_timeout 86400;
  }

  location /terminal/ {
    proxy_pass         http://127.0.0.1:7681/;
    proxy_http_version 1.1;
    proxy_set_header   Host              $host;
    proxy_set_header   X-Real-IP         $remote_addr;
    proxy_set_header   Upgrade           $http_upgrade;
    proxy_set_header   Connection        $connection_upgrade;
    proxy_read_timeout 86400;
    proxy_send_timeout 86400;
    proxy_buffering    off;
    proxy_cache        off;

  }
NGINXCONF

if [[ "${DESKTOP_ENABLED}" == "true" ]]; then
  cat >> /etc/nginx/sites-available/k16s <<'NGINXCONF'

  location /desktop/ {
    proxy_pass         http://127.0.0.1:6080/;
    proxy_http_version 1.1;
    proxy_set_header   Host              $host;
    proxy_set_header   X-Real-IP         $remote_addr;
    proxy_set_header   Upgrade           $http_upgrade;
    proxy_set_header   Connection        $connection_upgrade;
    proxy_read_timeout 86400;
    proxy_send_timeout 86400;
    proxy_buffering    off;
    proxy_cache        off;
  }
NGINXCONF
else
  log_skip "nginx /desktop/ route (K16S_DESKTOP=false)"
fi

cat >> /etc/nginx/sites-available/k16s <<'NGINXCONF'
}
NGINXCONF

sed -i \
  -e "s/__BIND_V4__/${BIND_V4}/" \
  -e "s/__BIND_V6__/${BIND_V6}/" \
  /etc/nginx/sites-available/k16s
log_info "Bind address: ${BIND_V4} / [${BIND_V6}]"

ln -sf /etc/nginx/sites-available/k16s /etc/nginx/sites-enabled/k16s
rm -f /etc/nginx/sites-enabled/default

nginx -t || die "nginx config test failed"
systemctl enable --now nginx
systemctl reload nginx
log_ok "nginx configured and running"

mark_done "nginx"
