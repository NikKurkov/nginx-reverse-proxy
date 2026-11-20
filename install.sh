#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    echo 'Usage: sudo ./install.sh'
    echo 'Install nginx-reverse-proxy on a fresh Debian or Ubuntu server.'
    exit 0
fi

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

[[ $# == 0 ]] || fail 'Usage: sudo ./install.sh'
[[ $EUID == 0 ]] || fail 'Run this installer with sudo.'
[[ -r /etc/os-release ]] || fail 'Cannot identify this Linux distribution.'
# shellcheck source=/dev/null
source /etc/os-release
case "${ID:-}:${VERSION_ID:-}" in
    debian:12|debian:13|ubuntu:22.04|ubuntu:24.04) ;;
    *) fail 'Use Debian 12/13 or Ubuntu 22.04/24.04.' ;;
esac
[[ -d /run/systemd/system ]] || fail 'This installer requires a running systemd.'
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ -f $script_dir/nginx-reverse-proxy ]] || fail 'Run install.sh from the cloned repository.'

stock_file() {
    local file=$1 expected actual
    [[ -f $file && ! -L $file ]] || return 1
    expected=$(dpkg-query -W -f='${Conffiles}\n' nginx-common 2>/dev/null |
        awk -v path="$file" '$1 == path { print $2 }')
    actual=$(md5sum <"$file")
    [[ -n $expected && ${actual%% *} == "$expected" ]]
}

# A stock welcome page is fine. Leave hand-written Nginx configuration alone.
if [[ -e /etc/nginx/nginx.conf || -L /etc/nginx/nginx.conf ]]; then
    stock_file /etc/nginx/nginx.conf || fail 'Found a custom /etc/nginx/nginx.conf.'
fi
shopt -s nullglob
for file in /etc/nginx/sites-available/* /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
    case $file in
        /etc/nginx/sites-available/default)
            stock_file "$file" && continue
            ;;
        /etc/nginx/sites-enabled/default)
            if [[ -L $file && $(readlink -f "$file") == /etc/nginx/sites-available/default ]] &&
                stock_file /etc/nginx/sites-available/default; then
                continue
            fi
            ;;
    esac
    fail "Found an existing Nginx site or config at $file. Use a fresh VPS."
done

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx certbot curl bind9-dnsutils ca-certificates
nginx -t

install -d -m 0755 /etc/nginx-reverse-proxy \
    /var/lib/nginx-reverse-proxy/acme/.well-known/acme-challenge \
    /etc/letsencrypt/renewal-hooks/deploy
defaults=/etc/nginx-reverse-proxy/defaults
if [[ ! -e $defaults ]]; then
    cat >"$defaults" <<'DEFAULTS'
# Optional defaults for new sites. Leave a value empty to enter it on add.
origin=
email=
DEFAULTS
fi

# Certbot's webroot authenticator leaves Nginx alone, including on renewals.
cat >/etc/letsencrypt/renewal-hooks/deploy/nginx-reverse-proxy <<'HOOK'
#!/bin/sh
set -eu
nginx -t
systemctl reload nginx
HOOK
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/nginx-reverse-proxy
install -m 0755 "$script_dir/nginx-reverse-proxy" /usr/local/bin/nginx-reverse-proxy
systemctl enable --now nginx.service certbot.timer

printf '\nInstalled. Add your first site with: sudo nginx-reverse-proxy add\n'
