# Jenkins operations

## Runtime limits and logs

The controller defaults to 4 GiB RAM, 2 CPUs, and 512 PIDs. The Docker proxy
defaults to 256 MiB RAM, 0.5 CPU, and 128 PIDs. Both use a capped
`on-failure:5` restart policy and rotate `json-file` logs at five 10 MiB files.
All values can be adjusted in `.env`.

Ephemeral agents default to 6 GiB and 2 CPUs. Docker Plugin 1324 exposes memory
and CPU limits for templates but does not expose a PID-limit field; PID limits
remain enforced for the long-running controller and socket proxy.

Run the Docker-storage threshold check manually or from cron:

```bash
make check-disk
MIN_DOCKER_FREE_GB=20 make check-disk
```

Bootstrap runs the same check before downloading or building images.

## Backup

Create a consistent backup with:

```bash
make backup
```

The script stops Jenkins when necessary, archives
`infrastructure-pipeline_jenkins_home`, writes a SHA-256 sidecar under
`backups/`, and restarts a controller that was running.

## Restore drill

Every backup must pass an isolated restore test:

```bash
scripts/verify-backup.sh backups/jenkins-home-YYYYmmddTHHMMSSZ.tar.gz
```

The check verifies the sidecar, extracts into a temporary Docker volume,
compares restored file counts, and deletes only that temporary volume.

For a production restore, keep the current volume untouched and restore into a
new name:

```bash
docker compose down
scripts/restore-jenkins.sh \
  backups/jenkins-home-YYYYmmddTHHMMSSZ.tar.gz \
  infrastructure-pipeline_jenkins_home_restored
```

Set
`JENKINS_HOME_VOLUME=infrastructure-pipeline_jenkins_home_restored` in `.env`,
run `make bootstrap`, and require the full smoke suite to pass. Rollback means
restoring the previous `JENKINS_HOME_VOLUME`; the restore tooling never
overwrites a non-empty volume.
