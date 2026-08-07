# compose-penpot

Docker Compose stack that runs a self-hosted [Penpot](https://penpot.app) instance
together with an [MCP](https://modelcontextprotocol.io) server, so AI assistants
and other MCP clients can interact with your Penpot files.

## Services

| Service            | Image                                       | Purpose                                   |
|---------------------|----------------------------------------------|--------------------------------------------|
| `penpot-frontend`   | `penpotapp/frontend:latest`                 | Web UI (port `9001`)                       |
| `penpot-backend`    | `penpotapp/backend:latest`                  | API / business logic                       |
| `penpot-exporter`   | `penpotapp/exporter:latest`                 | PDF/PNG/SVG export worker                  |
| `penpot-postgres`   | `postgres:15`                               | Database                                   |
| `penpot-redis`      | `redis:7`                                   | Cache / pub-sub                            |
| `penpot-mailcatch`  | `sj26/mailcatcher:latest`                   | Catches outgoing emails (port `1080` UI)   |
| `penpot-mcp`        | `ghcr.io/zcube/penpot-mcp-server:latest`    | MCP server exposing Penpot over MCP (port `3000`) |

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
- A `PENPOT_SECRET_KEY` (see below)
- A Penpot **access token** for the MCP server (see below)

## Getting started

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

4. Generate an access token: in Penpot, go to **Your account → Access tokens**
   and create a new token.

5. Add it to the same `.env` file (or export it before starting `penpot-mcp`):

   ```sh
   echo "PENPOT_ACCESS_TOKEN=<your-token>" >> .env
   docker compose up -d penpot-mcp
   ```

6. Point your MCP client at `http://localhost:3000/mcp` (health check at
   `http://localhost:3000/health`).

## Mail

Outgoing emails (registration, password reset, etc.) are captured by
Mailcatcher instead of being sent for real. View them at
[http://localhost:1080](http://localhost:1080).

## Validating the compose file

```sh
docker compose config --quiet
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

## License

This project is licensed under the **GNU General Public License v3.0** — see
the [LICENSE](./LICENSE) file for details.
