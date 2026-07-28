.PHONY: backup bootstrap check-disk check-docmost setup-docmost smoke

bootstrap:
	@./scripts/bootstrap.sh

smoke:
	@./scripts/smoke-test.sh

backup:
	@./scripts/backup-jenkins.sh

check-disk:
	@./scripts/check-disk-space.sh

check-docmost:
	@./docmost/setup.sh --check

setup-docmost:
	@./docmost/setup.sh
