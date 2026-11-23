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

- The `http://<elastic IP>` site serves the API and website over plain HTTP
  on the bare IP address. Remove it once nothing depends on it.
- `stroy.com.kg/staging-api/*` routes production-domain traffic to the
  staging API (used by `/billing/?stage=1`). Move staging to its own host.
