.PHONY: check install-bin

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
	sh -n bin/with-secrets
	sh -n bin/push-secrets
	sh -n bin/wait-for
	sh -n bin/test-wait-for.sh
	sh -n bin/test-with-secrets.sh
	sh -n bin/test-push-secrets.sh
	sh -n adapters/claude/hooks/test-check-chip-brief.sh
	sh -n adapters/claude/hooks/test-check-attention.sh
	sh scripts/test-sync.sh
	sh scripts/test-push-policy-sync.sh
	sh scripts/test-ensure-labels.sh
	sh scripts/test-check-links.sh
	sh scripts/test-check-action-pins.sh
	python3 scripts/check-action-pins.py .
	sh scripts/test-check-adrs.sh
	sh adapters/claude/hooks/test-check-chip-brief.sh
	sh adapters/claude/hooks/test-check-attention.sh
	sh bin/test-with-secrets.sh
	sh bin/test-push-secrets.sh
	sh bin/test-wait-for.sh

# Link the helpers in bin/ (not their tests) into ~/.local/bin.
install-bin:
	mkdir -p $(HOME)/.local/bin
	for f in with-secrets push-secrets wait-for; do ln -sf "$(CURDIR)/bin/$$f" "$(HOME)/.local/bin/$$f"; done
