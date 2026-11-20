#!/usr/bin/env bash
set -euo pipefail

# The container has no init. Use real Nginx and Certbot, with just the
# installer/reload calls to systemd translated into Nginx commands.
[[ -f /.dockerenv && -r /fixtures/acme.crt ]] || exit 1
mkdir -p /run/systemd/system /etc/nginx/sites-enabled
cat >/usr/bin/systemctl <<'SYSTEMCTL'
#!/bin/bash
case "$*" in
    'enable --now nginx.service certbot.timer') nginx ;;
    'reload nginx') nginx -s reload ;;
    daemon-reload|unmask*|*" preset "*) exit 0 ;;
    *) exit 1 ;;
esac
SYSTEMCTL
chmod 755 /usr/bin/systemctl

printf 'untouched\n' >/etc/nginx/sites-enabled/existing.conf
if /repo/install.sh; then
    echo 'Installer accepted a server with a custom site.' >&2
    exit 1
fi
grep -Fxq untouched /etc/nginx/sites-enabled/existing.conf
rm /etc/nginx/sites-enabled/existing.conf
/repo/install.sh
nginx-reverse-proxy list | grep -Fxq 'No managed sites.'

export REQUESTS_CA_BUNDLE=/fixtures/acme.crt
printf 'server = https://pebble:14000/dir\n' >>/etc/letsencrypt/cli.ini
curl -fsS --cacert "$REQUESTS_CA_BUNDLE" https://pebble:15000/roots/0 > /tmp/pebble-root.pem

mkdir /tmp/origin
printf 'origin reached\n' >/tmp/origin/index.html
python3 -m http.server 8080 --bind 127.0.0.1 --directory /tmp/origin >/tmp/origin.log 2>&1 &
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=origin.test \
    -addext subjectAltName=DNS:origin.test -keyout /tmp/origin.key \
    -out /usr/local/share/ca-certificates/origin.crt 2>/dev/null
update-ca-certificates >/dev/null
python3 - <<'PY' >/tmp/origin-tls.log 2>&1 &
import http.server
import json
import os
import ssl

class Origin(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/headers":
            return super().do_GET()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(json.dumps(dict(self.headers)).encode())

os.chdir("/tmp/origin")
server = http.server.HTTPServer(("127.0.0.1", 8443), Origin)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_3
context.load_cert_chain("/usr/local/share/ca-certificates/origin.crt", "/tmp/origin.key")
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
PY

config=/etc/nginx/sites-available/reverse-proxy
link=/etc/nginx/sites-enabled/reverse-proxy
fail_unless_rejected() {
    if "$@"; then
        echo 'Unexpected success.' >&2
        exit 1
    fi
}

fail_unless_rejected nginx-reverse-proxy add --bogus
fail_unless_rejected nginx-reverse-proxy add $'site.test\nextra' --yes
printf 'site.test\nbad domain\n' >/tmp/domains
fail_unless_rejected nginx-reverse-proxy add --file /tmp/domains --yes
test ! -e "$config-site.test.conf"

printf 'server { listen 80; server_name manual.test; return 204; }\n' >/etc/nginx/sites-enabled/manual.conf
manual_hash=$(sha256sum /etc/nginx/sites-enabled/manual.conf)
fail_unless_rejected nginx-reverse-proxy add manual.test --origin http://127.0.0.1:8080 --email admin@example.com --yes
test "$manual_hash" = "$(sha256sum /etc/nginx/sites-enabled/manual.conf)"
test ! -e "$config-manual.test.conf"
rm /etc/nginx/sites-enabled/manual.conf

cat >/etc/nginx-reverse-proxy/defaults <<'DEFAULTS'
origin=http://127.0.0.1:8080
email=admin@example.com
DEFAULTS
printf '# first site\n\n SITE.TEST # example\n' >/tmp/domains
nginx-reverse-proxy add --file /tmp/domains --www --yes
initial_hash=$(sha256sum "$config-site.test.conf")
fail_unless_rejected nginx-reverse-proxy add www.site.test --yes
test "$initial_hash" = "$(sha256sum "$config-site.test.conf")"

for host in site.test www.site.test; do
    curl -sfSI --retry 4 --retry-all-errors "http://$host/example?q=1" | tr -d '\r' |
        grep -Fix "Location: https://$host/example?q=1"
    curl -fsS --retry 4 --retry-all-errors --cacert /tmp/pebble-root.pem "https://$host/" |
        grep -Fx 'origin reached'
done

fail_unless_rejected nginx-reverse-proxy add missing.test --yes
test ! -e "$config-missing.test.conf"
test ! -L "$link-missing.test.conf"
fail_unless_rejected env REQUESTS_CA_BUNDLE=/dev/null nginx-reverse-proxy add bad.test --yes
test ! -e "$config-bad.test.conf"
test ! -L "$link-bad.test.conf"

nginx-reverse-proxy add secure.test --origin https://127.0.0.1:8443 --tls-name origin.test --yes
curl -fsS --retry 4 --retry-all-errors --cacert /tmp/pebble-root.pem https://secure.test/ |
    grep -Fx 'origin reached'
curl -fsS --cacert /tmp/pebble-root.pem https://secure.test/headers \
    -H 'X-Forwarded-Host: attacker.test' -H 'X-Forwarded-Port: 80' -H 'Forwarded: host=attacker.test' |
    python3 -c 'import json, sys; h = json.load(sys.stdin); assert h["X-Forwarded-Host"] == "secure.test"; assert h["X-Forwarded-Port"] == "443"; assert "Forwarded" not in h'

serial() {
    openssl s_client -connect site.test:443 -servername site.test </dev/null 2>/dev/null |
        openssl x509 -noout -serial
}
before=$(serial)
certbot renew --cert-name site.test --force-renewal --non-interactive --no-random-sleep-on-renew
expected=$(openssl x509 -in /etc/letsencrypt/live/site.test/fullchain.pem -noout -serial)
test "$before" != "$expected"
for _ in {1..10}; do
    [[ $(serial) != "$expected" ]] || break
    sleep 1
done
test "$(serial)" = "$expected"

nginx-reverse-proxy remove site.test --yes
nginx-reverse-proxy list | grep -Fx $'site.test\tdisabled'
test -f "$config-site.test.conf"
test -s /etc/letsencrypt/live/site.test/fullchain.pem
test ! -L "$link-site.test.conf"
nginx -t
