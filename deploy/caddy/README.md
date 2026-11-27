# Edge proxy (Caddy)

`Caddyfile` is the production edge configuration, copied verbatim from the
host (`/opt/projects/StroyCaddy/Caddyfile`, mounted read-only at
`/etc/caddy/Caddyfile`). Caddy obtains and renews the Let's Encrypt
certificates itself; its state lives in the `stroy_caddy_data` and
`stroy_caddy_config` volumes. Keep this copy in sync with the host: change it
here first, then copy it to the host and reload.

The container is not managed by Compose. It was started as:

```bash
docker run -d --name stroy-caddy --restart unless-stopped \
  --network stroy_default -p 80:80 -p 443:443 \
  -v /opt/projects/StroyCaddy/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v stroy_caddy_data:/data -v stroy_caddy_config:/config \
  caddy:2.11.4-alpine caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
```

Apply a change without downtime:

```bash
sudo install -m 0644 deploy/caddy/Caddyfile /opt/projects/StroyCaddy/Caddyfile
docker exec stroy-caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker exec stroy-caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

## Known follow-ups

- The `http://<elastic IP>` site now only redirects to HTTPS (2026-11-27);
  delete it once the address is retired.
- The `/staging-api` route on the production domain was removed
  (2026-11-27). If staging returns, give it its own host and Docker network.
