# Recovery

<!-- Deployed products with user data, and infrastructure (P19, P20). How to
get back to working after losing a host, a database or an account. Written to
be followed under stress by someone with no context. Budget: 20 KB. -->

**Last tested:** <YYYY-MM-DD> — <what was restored, how long it took, result>
**Next test due:** <YYYY-MM-DD>

## Targets

| What | Can lose at most (RPO) | Back within (RTO) |
|---|---|---|
| <database> | <e.g. 24 h> | <e.g. 4 h> |

## What is backed up

| Data | Method | Frequency | Stored | Retention | Encrypted |
|---|---|---|---|---|---|
| <data> | <tool> | <daily> | <where> | <30 d> | <yes, key name> |

## Scenarios

### <Lost host / corrupted database / lost account>

**Signs:** <what you would notice>
**Needs:** <access, secrets by name, tools>

1. <step>
   ```bash
   <command>
   ```
   Expect: <result>

**Check it worked:** <how>

## Not recoverable

<!-- Be explicit. Each item is a decision or a gap. -->
- <data or state> — <why, and whether that is accepted (ADR) or a gap>
