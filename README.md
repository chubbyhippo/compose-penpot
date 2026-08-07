# compose-penpot

Docker Compose stack that runs a self-hosted [Penpot](https://penpot.app) instance
together with the official [MCP](https://modelcontextprotocol.io) server, so AI
assistants and other MCP clients can interact with your Penpot files.

## Services

| Service            | Image                                       | Purpose                                                     |
|---------------------|----------------------------------------------|---------------------------------------------------------------|
| `penpot-frontend`   | `penpotapp/frontend:latest`                 | Web UI + nginx proxy (port `9001`), also proxies `/mcp/*`      |
| `penpot-backend`    | `penpotapp/backend:latest`                  | API / business logic                                          |
| `penpot-exporter`   | `penpotapp/exporter:latest`                 | PDF/PNG/SVG export worker                                      |
| `penpot-postgres`   | `postgres:15`                               | Database                                                       |
| `penpot-redis`      | `redis:7`                                   | Cache / pub-sub                                                |
| `penpot-mailcatch`  | `sj26/mailcatcher:latest`                   | Catches outgoing emails (port `1080` UI) — `compose.yaml` only |
| `penpot-mcp`        | `penpotapp/mcp:latest`                      | Official Penpot MCP server, reached via the frontend's proxy   |

The `penpot-mcp` service has no published port of its own: `penpot-frontend`'s
nginx config proxies `/mcp/*` to it internally (`http://penpot-mcp:4401` for
HTTP/SSE, `:4402` for the plugin-bridge websocket), so MCP clients always
connect through the frontend's port (`9001`).

## Local development

`compose-local.yaml` is a trimmed-down stack for local development: it drops
Mailcatcher and Traefik labels, keeping Penpot's core services (including the
exporter, which `penpot-frontend`'s nginx config requires) plus the MCP
server.

```sh
docker compose -f compose-local.yaml up -d
```

## Requirements

- Docker Engine with the Compose plugin (`docker compose`)
- A `PENPOT_SECRET_KEY` (see below) — the only required secret; the MCP
  server itself needs no access token

## Getting started

### Automated setup

`setup.sh` automates the whole flow: it generates and persists
`PENPOT_SECRET_KEY` in `.env`, starts every service (including `penpot-mcp`),
waits for the backend to become reachable, and registers (or logs into, if it
already exists) an account. `setup-local.sh` is the same script defaulting to
`compose-local.yaml`.

```sh
./setup.sh [compose-file] [email] [password] [fullname]
./setup-local.sh [email] [password] [fullname]

# examples
./setup.sh
./setup.sh compose-local.yaml me@example.com 'Sup3rSecret!' "My Name"
./setup-local.sh me@example.com 'Sup3rSecret!' "My Name"
```

It's safe to run again later (e.g. after `docker compose down -v`): it
reuses the account if it already exists.

Once it completes:

- Penpot UI: [http://localhost:9001](http://localhost:9001) (log in with the
  email/password you passed, defaults are `admin@example.com` /
  `ChangeMe123!`)
- MCP endpoint: `http://localhost:9001/mcp/stream` (legacy SSE:
  `http://localhost:9001/mcp/sse`)

To use design-editing tools (`execute_code`, `export_shape`, ...) against a
real file, open it in the Penpot UI and connect the **Penpot MCP Plugin**
from within that file — those tools operate on the plugin-bridge session, not
just the REST API.

### Manual setup

1. Set a secret key (used by `penpot-backend`/`penpot-exporter` to derive
   session and invitation tokens) in a `.env` file next to `compose.yaml`:

   ```sh
   echo "PENPOT_SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_urlsafe(64))')" >> .env
   ```

2. Start the stack:

   ```sh
   docker compose up -d
   ```

3. Open Penpot at [http://localhost:9001](http://localhost:9001) and register an
   account (registration is enabled by default).

4. Point your MCP client at `http://localhost:9001/mcp/stream` (legacy SSE at
   `http://localhost:9001/mcp/sse`). No access token is required — the MCP
   container runs in multi-user/plugin-bridge mode behind the frontend proxy.

## MCP tools

Once connected, the server exposes:

- `high_level_overview` — read this first; returns usage instructions for the
  Penpot API and the other tools.
- `execute_code` — runs JavaScript in the Penpot plugin context (needs the
  Penpot MCP Plugin connected inside an open file).
- `penpot_api_info` — looks up Penpot API type/member documentation.
- `export_shape` — exports a shape (or `'selection'`/`'page'`) as PNG or SVG.

You can sanity-check the endpoint manually once the stack is up:

```sh
curl -s -X POST http://localhost:9001/mcp/stream \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

## Mail

Outgoing emails (registration, password reset, etc.) are captured by
Mailcatcher instead of being sent for real (`compose.yaml` only). View them at
[http://localhost:1080](http://localhost:1080).

## Validating the compose file

```sh
docker compose config --quiet
docker compose -f compose-local.yaml config --quiet
```

## Data migration

`export.sh` and `import.sh` back up and restore a full instance (database +
uploaded assets), useful for moving Penpot to another host or environment.

Export (stack must be running):

```sh
./export.sh compose.yaml ./backups
```

This writes `penpot-db-<timestamp>.dump.gz` (a `pg_dump -Fc` database dump)
and `penpot-assets-<timestamp>.tar.gz` (the assets volume) into `./backups`.

Import (into a fresh or existing stack — **this overwrites the target
database and assets volume**):

```sh
./import.sh backups/penpot-db-<timestamp>.dump.gz backups/penpot-assets-<timestamp>.tar.gz compose.yaml
```

Both scripts accept an alternate compose file as an argument, so they also
work with `compose-local.yaml`.

## Troubleshooting

- **`docker-credential-secretservice: error while loading shared libraries:
  libsecret-1.so.0` / `error getting credentials`**: your Docker CLI is
  configured to use a credential helper (`~/.docker/config.json`) that isn't
  installed in this environment. It only affects registry auth for `docker
  compose pull`; if the images are already present locally you can work
  around it with `docker compose up -d --pull never`, or fix/remove the
  `credsStore` entry in your Docker config.
- **`failed to connect to the backend: timed out dialing Hyper-V socket`**:
  transient Docker Desktop/daemon hiccup on Windows. Retry the command; if it
  persists, restart Docker Desktop.

## License

This project is licensed under the **GNU General Public License v3.0** — see
the [LICENSE](./LICENSE) file for details.
