.PHONY: check

# Same checks as CI.
check:
	python3 scripts/build-adapters.py --check
	sh -n scripts/sync-policy.sh
	sh -n scripts/push-policy-sync.sh
	sh -n scripts/test-push-policy-sync.sh
	sh -n scripts/test-sync.sh
	sh -n scripts/ensure-labels.sh
	sh -n scripts/test-ensure-labels.sh
	sh -n scripts/test-check-action-pins.sh
	sh -n scripts/test-check-adrs.sh
	sh -n adapters/claude/hooks/session-start.sh
	sh -n adapters/claude/hooks/test-check-chip-brief.sh
	sh -n adapters/claude/hooks/test-check-attention.sh
	sh scripts/test-sync.sh
	sh scripts/test-push-policy-sync.sh
	sh scripts/test-ensure-labels.sh
	sh scripts/test-check-links.sh
	sh scripts/test-check-action-pins.sh
	sh scripts/test-check-adrs.sh
	sh adapters/claude/hooks/test-check-chip-brief.sh
	sh adapters/claude/hooks/test-check-attention.sh
