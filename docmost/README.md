# Docmost module

This module follows the official Docmost Docker architecture and runs:

- Docmost;
- PostgreSQL;
- Redis with append-only persistence and authentication.

PostgreSQL and Redis are reachable only from the private `docmost` network.
Only Docmost is published, at `http://127.0.0.1:3000/` by default.

## First start

`make bootstrap` generates the database, application, Redis, and owner
credentials when their `.env` values are empty. It starts Docmost, waits for
`/api/health`, and uses the first-run API to create the configured workspace
and owner. Repeated setup calls do not change an existing workspace.

Run the setup independently or check readiness with:

```sh
make setup-docmost
make check-docmost
```

The default owner email is `admin@docmost.local`. Its generated password
remains in the ignored local `.env` file as `DOCMOST_OWNER_PASSWORD`.

## Persistent state

Back up these volumes together:

- `infrastructure-pipeline_docmost_db`;
- `infrastructure-pipeline_docmost_redis`;
- `infrastructure-pipeline_docmost_storage`.

Image tags and immutable registry digests are stored in `toolchain.lock`.
Runtime settings are documented in the root `.env.example`.

Official deployment reference:
<https://docmost.com/docs/installation>
