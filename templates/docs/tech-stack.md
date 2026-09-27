# Tech stack

<!-- Product repos (P19); others when relevant. What we use, which version
policy, and why, at a glance. Reasons live in ADRs; this is the index. Budget:
20 KB. -->

**Updated:** <YYYY-MM-DD> · **Next review:** <YYYY-MM-DD>

**<Headline: the stack's character in one line, e.g. "Boring on purpose".>**
<Two sentences: the principles behind the choices.>

Kind: **write** = code we write · **build on** = open source · **rent** = a
service · **unconfirmed** = still to be proven by a spike.

<!-- One section per layer, each with a one-line intent. Typical layers:
Clients, API, Backend, Services we rent, Delivery and quality. -->

### <Layer> — <one-line intent>

| Choice | Kind | Version policy | Role, in one line | Decision |
|---|---|---|---|---|
| <choice> | write / build on / rent | <e.g. active LTS, pinned> | <what it does for us> | ADR-NNNN |

## Rules for adding dependencies

- Exact version pins; a new dependency is justified in its PR, a novel one
  (new runtime, framework, service or vendor) gets an ADR (P20)
- <licence allow-list, maintenance signals, who approves>

## Known debts and upgrades due

| Item | Why it matters | When |
|---|---|---|
| <upgrade> | <risk> | <date or trigger> |

## Rejected

<!-- Short list so nobody re-proposes them without new evidence. -->
- <option> — <reason> (ADR-NNNN)
