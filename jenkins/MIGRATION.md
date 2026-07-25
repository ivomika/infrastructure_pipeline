# Compose project-name migration

The historical project name was misspelled as `infrastructure-pipelinse`.
Changing it to `infrastructure-pipeline` changes the Compose-managed Jenkins
volume name.

`make bootstrap` runs `scripts/migrate-compose-project.sh` before the new stack
starts. When the legacy volume exists and the new one does not, the script:

1. stops the legacy Compose containers without deleting their volumes;
2. creates `infrastructure-pipeline_jenkins_home`;
3. copies the old volume through the digest-pinned Jenkins base image;
4. compares source and destination entry counts;
5. keeps `infrastructure-pipelinse_jenkins_home` unchanged for rollback.

The migration refuses to overwrite a pre-existing destination volume unless it
has the migration label for the exact source. After the new stack has been
backed up and verified, an operator may remove the retained legacy volume
manually.
