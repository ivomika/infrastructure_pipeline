.PHONY: backup bootstrap check-disk check-plane smoke start

bootstrap:
	@./scripts/bootstrap.sh

start:
	@./scripts/start.sh

smoke:
	@./scripts/smoke-test.sh

backup:
	@./scripts/backup-jenkins.sh

check-disk:
	@./scripts/check-disk-space.sh

check-plane:
	@./scripts/bootstrap.sh --check
