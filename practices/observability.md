# Observability contract

Version: **1**. What every deployed project exposes so that a routine, a
dashboard or a person can tell whether it is healthy, without knowing its
internals. Required by P20 for deployed products and infrastructure.
Consumers state which contract version they support; a breaking change bumps
the version.

Pull comes first: consumers poll. Push is optional, because a consumer may sit
on a private network that deployed services cannot reach.

## 1. Health

- HTTP services: `GET /healthz`, no authentication, 200 when healthy, body
  `{"status": "ok", "version": "<release>"}`. Non-200 or another status value
  means unhealthy. It checks the process and its hard dependencies, fast (under
  one second), and exposes nothing sensitive.
- Anything without HTTP (a runner pool, a server, a scheduled job) names in the
  manifest the API call or command that answers the same question.

## 2. Manifest

A YAML block at the top of `docs/operations.md` (`templates/docs/operations.md`),
between `<!-- observability:begin -->` and `<!-- observability:end -->`.
Consumers import it; nobody keeps a second copy in sync by hand.

```yaml
contract: 1
environments:
  - name: production
    url: https://example.com
    health: https://example.com/healthz        # or: command / api
    version: https://example.com/healthz       # where the release is read
signals:
  logs:   { where: <service>, query: <exact command or URL>, retention: 30d }
  errors: { where: <error tracker project URL> }
  uptime: { where: <uptime check URL>, interval: 1m }
  metrics: { where: <dashboard URL> }          # optional
alerts:
  - name: down
    condition: health failing for 3 minutes
    severity: page                             # page | notify | log
    notifies: <channel name>
    runbook: docs/runbooks/down.md
  - name: error-spike
    condition: errors above 5x the 7-day baseline for 10 minutes
    severity: notify
    notifies: <channel name>
    runbook: docs/runbooks/error-spike.md
access:
  - { signal: errors, needs: <secret name>, stored: <where I keep it> }
normal:
  error_rate: <baseline>
  notes: <what routine noise looks like>
```

Rules: every alert has a runbook, with paths relative to the repo root; secrets are named, never included (P10);
unknown signals are omitted, not invented.

## 3. Alerts as code

Alerts are defined in the manifest and reviewed like code. A tool's UI may
implement them, but the manifest is the source; a mismatch is a finding.

## 4. Minimum per type

| | Deployed product | Infrastructure |
|---|---|---|
| Health endpoint or equivalent | ✓ | ✓ |
| External uptime check | ✓ | ✓ |
| Queryable structured logs | ✓ | ✓ |
| Error tracking with release tags | ✓ | — |
| Alerts `down` and `error-spike`, reaching my phone | ✓ | `down` |
| Disk, backup success, certificate expiry alerts | if stateful | ✓ |

Tool choice is per project and recorded as an ADR.

## 5. Push (optional)

Where the receiver is reachable, services may export OpenTelemetry over OTLP.
The destination comes only from the standard `OTEL_EXPORTER_OTLP_ENDPOINT`
variable set by the deployment; the project never names it.

## 6. Consumers

- The daily triage routine reads the manifest, queries each signal since its
  last run, compares with `normal`, and reports what is new, recurring or
  worse. A missing or stale manifest is itself reported.
- A dashboard imports manifests to register environments, poll health and
  evaluate alerts.
