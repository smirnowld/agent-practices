.PHONY: check

# Same checks as CI.
check:
	python3 scripts/build-adapters.py --check
	sh -n scripts/sync-policy.sh
	sh -n scripts/test-sync.sh
	sh -n adapters/claude/hooks/session-start.sh
	sh scripts/test-sync.sh
