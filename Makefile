.PHONY: bootstrap smoke

bootstrap:
	@./scripts/bootstrap.sh

smoke:
	@./scripts/smoke-test.sh
