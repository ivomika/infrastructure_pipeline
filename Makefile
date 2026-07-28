.PHONY: backup bootstrap check-disk check-docmost check-plane setup-docmost smoke start

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

check-docmost:
	@./docmost/setup.sh --check

setup-docmost:
	@./docmost/setup.sh

check-plane:
	@./scripts/bootstrap.sh --check
