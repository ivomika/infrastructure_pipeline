# Plane module

This module runs Plane Community Edition and all services required by the
official self-hosted architecture:

- Plane web, space, administration, live, API, worker, beat, and migration
  services;
- PostgreSQL;
- Valkey;
- RabbitMQ;
- MinIO object storage;
- the Plane reverse proxy.

Only the reverse proxy is published, at `http://127.0.0.1:9010/` by default.
All data services are reachable only through the private `plane` network.
Plane containers use explicit names such as `infrastructure-pipeline-plane-api`
and therefore do not have Compose's replica suffix (`-1`).

## First start

Run:

```sh
make bootstrap
```

Bootstrap generates all Plane secrets when their values in `.env` are empty,
validates the port and immutable image locks, starts the complete stack, and
waits for Plane to answer. Open the URL and complete **Secure your instance**;
the account created there becomes the Plane instance administrator.

To check Plane without starting it:

```sh
make check-plane
```

## Persistent state

Back up these named volumes together:

- `infrastructure-pipeline_plane_db`;
- `infrastructure-pipeline_plane_redis`;
- `infrastructure-pipeline_plane_rabbitmq`;
- `infrastructure-pipeline_plane_minio`.

The root `.env.example` contains runtime settings. Image tags and immutable
registry digests are stored in `toolchain.lock`.

Official references:

- <https://developers.plane.so/self-hosting/methods/docker-compose>
- <https://developers.plane.so/self-hosting/plane-architecture>
