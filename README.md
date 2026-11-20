# Nginx reverse proxy

[Русский](README.ru.md)

Put a VPS in front of an existing website. Nginx forwards requests to the server
hosting the site. Certbot issues and renews the public HTTPS certificate.

## Install and add a site

Use a fresh Debian 12/13 or Ubuntu 22.04/24.04 VPS with systemd and root or
`sudo` access. The installer stops if it finds custom Nginx configuration.

- Point the domain's A record at the VPS. Keep an AAAA record only if the VPS
  serves that IPv6 address. Use DNS-only mode if your DNS provider offers a proxy.
- Open incoming TCP ports **80** and **443**. Keep port 80 open for renewals.
- Have the origin URL ready. The VPS must be able to reach it, and the origin
  must serve your site for the public hostname. Use an HTTP or HTTPS URL
  without a path.

Run on the VPS over SSH. Omit `sudo` if you're logged in as root.

```sh
sudo apt update && sudo apt install -y git
git clone https://github.com/NikKurkov/nginx-reverse-proxy.git
cd nginx-reverse-proxy
sudo ./install.sh
sudo nginx-reverse-proxy add
```

Enter the domain, origin URL and a Let's Encrypt email address, then confirm.
The command checks DNS, requests a certificate and enables the HTTPS redirect.
Open your domain in a browser when it prints `Ready`.

## Manage sites

```sh
sudo nginx-reverse-proxy add example.com \
  --origin http://192.0.2.20:8080 --email admin@example.com --yes
sudo nginx-reverse-proxy list
sudo nginx-reverse-proxy remove example.com
```

- Use `--www` to include the `www` hostname. Point its DNS at the VPS first.
- Use `add --file domains.txt` with the same options for a list with one domain
  per line. If a site fails, the command rolls back that site's Nginx config and stops.
- Set `origin=` and `email=` in `/etc/nginx-reverse-proxy/defaults` to reuse
  them. For an HTTPS origin reached by IP, pass its certificate hostname with
  `--tls-name`.
- `remove` keeps the config and certificate. An existing config is never
  overwritten by `add`. A disabled site's certificate can expire.

If adding a site fails, check DNS and port 80, then read Certbot's output.
For a 502 response, check the origin from the VPS and look in
`/var/log/nginx/error.log`. Run `nginx-reverse-proxy --help` for all options.

[MIT license](LICENSE)
