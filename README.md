# Nginx reverse proxy

[По-русски](README.ru.md)

Put a VPS in front of a website that already runs on another server. Nginx
accepts requests for your domain and forwards them to the server hosting the
site. Certbot gets the public HTTPS certificate and renews it.

## Before you start

- Use a fresh Debian 12, Debian 13, Ubuntu 22.04 LTS or Ubuntu 24.04 LTS VPS
  running systemd. You need SSH access and root or `sudo`. The installer stops
  if it finds an existing custom Nginx configuration.
- Find the public IP of the VPS. At your DNS provider, point the domain's
  **A** record to that IPv4 address. Keep an **AAAA** record only if IPv6 on
  the VPS works and the record points to it. To use `www`, set up its DNS
  too, with its own address record or a CNAME to the main domain. Use DNS-only
  mode if your DNS provider also offers a proxy.
- Allow incoming TCP **80** and **443** in the hosting firewall and on the VPS
  if it has its own firewall. Keep port 80 open for renewals.
- Have the URL of the server hosting the site handy. The VPS must be able to
  reach it, and that server must serve the site for the public hostname.
  For example, a web app might listen at `http://192.0.2.20:8080`.

## Add your first site

Run these commands over SSH on the VPS. If you are logged in as root, omit
`sudo`. Install Git first if your image does not include it.

```sh
sudo apt update && sudo apt install -y git
git clone https://github.com/NikKurkov/nginx-reverse-proxy.git
cd nginx-reverse-proxy
sudo ./install.sh
sudo nginx-reverse-proxy add
```

Enter your public domain without `https://`, the origin URL, and an email for
the Let's Encrypt account. Read the summary and answer `y` to continue. The
script first checks that each DNS address serves a test request over HTTP.
Once the certificate is ready, the site redirects HTTP traffic to HTTPS.

Open your site in a browser or check it from your own computer:

```sh
curl -I https://example.com/
```

Use your own domain in the command. You should see the response from your
site. If the origin does not accept HEAD requests, open the site in a browser
or run `curl https://example.com/`.

## Add more sites

Run without prompts by adding `--yes` and supplying the required values.
`--www` adds `www.example.com` to the Nginx site and the same certificate.

```sh
sudo nginx-reverse-proxy add example.com \
  --origin http://192.0.2.20:8080 --email admin@example.com --www --yes
```

To reuse an origin or email, set `origin=` or `email=` in
`/etc/nginx-reverse-proxy/defaults` with `sudoedit`. Command-line values take
precedence. These defaults apply to sites you add afterwards.

For an HTTPS origin, use its HTTPS URL. Nginx checks the certificate against
the VPS's trusted CA store. If you connect by IP, provide the hostname on
the origin's certificate with `--tls-name`:

```sh
sudo nginx-reverse-proxy add example.net \
  --origin https://192.0.2.20:8443 --tls-name origin.example.net \
  --email admin@example.net --yes
```

An origin URL can contain a hostname or IP and an optional port. Put an IPv6
address in square brackets. Use an origin URL without a path, query, or
credentials. Nginx forwards the original path and public hostname.

For several sites with the same origin, put one domain on each line in
`domains.txt`. Empty lines and text after `#` are ignored.

```sh
sudo nginx-reverse-proxy add --file domains.txt \
  --origin http://192.0.2.20:8080 --email admin@example.com --yes
```

A bad or repeated name stops the list before any site is added. If a later
site fails its DNS check or certificate request, processing stops there.
Sites already added stay online. Fix the problem, then retry with the
remaining domains.

## List or disable sites

```sh
sudo nginx-reverse-proxy list
sudo nginx-reverse-proxy remove example.com
```

`remove` disables the Nginx site and keeps its config and certificate.
Certbot's HTTP challenge needs the site to be enabled. While a site is
disabled, its certificate can expire.

The site configs are in `/etc/nginx/sites-available/` and named
`reverse-proxy-DOMAIN.conf`. To restore a disabled site, an administrator
can recreate its symlink in `/etc/nginx/sites-enabled/`, check the
configuration with `sudo nginx -t`, and reload with
`sudo systemctl reload nginx`. Check the certificate before putting the
site back into use. The `add` command refuses to overwrite a saved config.

## If something fails

| Symptom | Where to look |
| --- | --- |
| The DNS or HTTP check fails | Check A and AAAA records for every requested name, including `www`. Wait for old DNS answers to expire. Check port 80 and make sure the VPS can reach its own public address. |
| The certificate request fails | Read the Certbot output and `/var/log/letsencrypt/letsencrypt.log`. Check the DNS records, public access to port 80 and any CAA records. |
| The site returns 502 | Check the origin address and port from the VPS. For an HTTPS origin, check the certificate chain and the name passed to `--tls-name`. Nginx logs details in `/var/log/nginx/error.log`. |
| HTTPS works, but renewal fails | Keep the domain pointed at the VPS and port 80 open. Check `systemctl status certbot.timer` and try `sudo certbot renew --dry-run`. |

When adding a site fails, the command removes the new Nginx config and reloads
the previous configuration. If Certbot had already issued a certificate, it
is kept for a retry.

## Development

`bash tests/check-cli.sh` checks the command-line help and basic argument
handling. With Docker and OpenSSL installed, run
`bash tests/smoke.sh debian:12-slim` for a full test with Nginx, Certbot and a
local ACME server. The containers use an isolated network and a test CA.

MIT licensed.
