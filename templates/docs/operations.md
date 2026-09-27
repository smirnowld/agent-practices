# Operations

<!-- Deployed products and infrastructure (P19, P20). How to tell it is
healthy and what to do when it is not. The manifest block is the
observability contract (practices/observability.md); routines and dashboards
read it, so keep it valid YAML and current. Budget: 30 KB. -->

<!-- observability:begin -->
```yaml
contract: 1
environments:
  - name: <production>
    url: <https://...>
    health: <https://.../healthz>          # or: command: <...> / api: <...>
    version: <https://.../healthz>
signals:
  logs:   { where: <service>, query: <exact command or URL>, retention: <30d> }
  errors: { where: <error tracker project URL> }
  uptime: { where: <uptime check URL>, interval: <1m> }
alerts:
  - { name: down, condition: <...>, severity: page, notifies: <channel>, runbook: docs/runbooks/down.md }
  - { name: error-spike, condition: <...>, severity: notify, notifies: <channel>, runbook: docs/runbooks/error-spike.md }
access:
  - { signal: <errors>, needs: <SECRET_NAME>, stored: <where I keep it> }
normal:
  error_rate: <baseline>
  notes: <routine noise>
```
<!-- observability:end -->

**Updated:** <YYYY-MM-DD>

## Where it runs

| Environment | Hosting | Deploys from | How | Link |
|---|---|---|---|---|
| <production> | <provider, region> | <branch / tag> | <automatic / manual> | <URL> |

## Deploy and roll back

- Deploy: <command or "automatic on merge to main">
- Roll back: <exact steps>, see [runbooks/rollback.md](runbooks/rollback.md)

## Daily health, at a glance

<!-- What the daily triage checks, in plain words, and what "normal" looks
like. Mirrors the manifest; the manifest wins. -->

## Alerts

<!-- Human-readable view of the manifest's alerts. Every alert has a runbook. -->

| Alert | Fires when | Reaches | Runbook |
|---|---|---|---|
| down | <condition> | <channel> | [down](runbooks/down.md) |

## Secrets

| Name | Used by | Stored | Rotation |
|---|---|---|---|
| <SECRET_NAME> | <component> | <where> | <how often, how> |

## Backups

<What is backed up, how often, where, retention, and when a restore was last
tested. Recovery steps: [recovery.md](recovery.md).>
