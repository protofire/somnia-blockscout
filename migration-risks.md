# Migration Risks — v8.1.1 → v9.3.3

## High Risk (Lock Hot Tables)

| Migration | Table(s) | Operation | Risk |
|-----------|----------|-----------|------|
| `20251115202635` | `tokens`, `token_instances` | DROP INDEX + DROP/RECREATE FK | ACCESS EXCLUSIVE on hot tables — blocks token transfer writes |
| `20251202092200` | `contract_methods` | CREATE UNIQUE INDEX (non-concurrent) | ACCESS EXCLUSIVE for full index build duration |
| `20250718092418` | `proxy_implementations` | UPDATE full table + ALTER ADD 2 columns | ROW EXCLUSIVE scan + ACCESS EXCLUSIVE |

## Medium Risk

| Migration | Table | Operation | Risk |
|-----------|-------|-----------|------|
| `20250714093329` | `tokens` | ALTER ADD `transfer_count` (nullable, no default) | Fast metadata-only in PG11+, but momentary ACCESS EXCLUSIVE |
| `20250725162308` | `tokens` | UPDATE SET skip_metadata = null | ROW EXCLUSIVE scan on matching rows |
| `20250820121833` | `signed_authorizations` | MODIFY column type (chain_id) | ACCESS EXCLUSIVE + possible row rewrite |
| `20250704124014` | `event_notifications` | TRUNCATE + ALTER ADD timestamps | ACCESS EXCLUSIVE (table likely small) |

## Safe (New Tables / Concurrent / Small Tables)

All CREATE TABLE migrations, `20250613144606` (concurrent index drop), DELETE from `migrations_status`, small account table drops.


