#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log_step "nginx (reverse proxy)"

already_done "nginx" && { log_skip "nginx"; exit 0; }

apt_install nginx

cat > /etc/nginx/sites-available/ckx <<'NGINXCONF'
map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}

server {
  listen 80 default_server;
  listen [::]:80 default_server;
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

    # Prevent ttyd from sending gzip so sub_filter can rewrite HTML
    proxy_set_header   Accept-Encoding   "";
    sub_filter '<head>' '<head><link rel="icon" href="/favicon.ico" sizes="any">';
    sub_filter_once    on;
  }
}
NGINXCONF

ln -sf /etc/nginx/sites-available/ckx /etc/nginx/sites-enabled/ckx
rm -f /etc/nginx/sites-enabled/default

nginx -t || die "nginx config test failed"
systemctl enable --now nginx
systemctl reload nginx
log_ok "nginx configured and running"

mark_done "nginx"
