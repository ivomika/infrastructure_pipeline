.PHONY: backup bootstrap check-disk smoke

bootstrap:
	@./scripts/bootstrap.sh

smoke:
	@./scripts/smoke-test.sh

backup:
	@./scripts/backup-jenkins.sh

check-disk:
	@./scripts/check-disk-space.sh
