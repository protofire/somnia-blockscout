# Migration Risk Analysis: v9.3.2 → v10.2.6

## Summary

| Risk Level | Count |
|---|---|
| 🔴 High | 2 |
| 🟡 Medium | 3 |
| 🟢 Safe | 7 |

---

## 🔴 High Risk

### `20250908062439_add_call_type_enum_to_internal_transactions.exs`
**Operation:** `ALTER TABLE internal_transactions` — adds new `call_type_enum` column (enum type), drops/creates CHECK constraints with `validate: false`.

**Risk:** The `internal_transactions` table is one of the largest and hottest tables in a high-TPS chain like Somnia. `ALTER TABLE ADD COLUMN` with a non-null default acquires a full table lock. This migration adds a nullable column (safe) but also drops and re-creates `CHECK` constraints — these use `validate: false` which avoids a full table scan, but the `DROP CONSTRAINT` DDL still requires a lock.

**Recommendation:** Run during low-traffic window. Monitor replication lag. The `validate: false` flag mitigates the scan risk.

---

### `20250915135943_create_transaction_errors.exs`
**Operation:** `ALTER TABLE internal_transactions` — adds `error_id` column (smallint, nullable), drops 2 `CHECK` constraints and creates 2 new ones (all `validate: false`). Also creates new `transaction_errors` table and unique index.

**Risk:** Same as above — multiple DDL operations on `internal_transactions`. The `validate: false` on constraints avoids table scans, but the column add + constraint drops/creates are multiple lock acquisitions on a hot table.

**Recommendation:** Run during maintenance window. The new `transaction_errors` table and index creation are safe (new table). The `internal_transactions` ALTER is the risky part.

---

## 🟡 Medium Risk

### `20250812000000_internal_transactions_drop_not_null_constraints.exs`
**Operation:** `ALTER TABLE internal_transactions` — modifies `trace_address` and `value` columns to be nullable.

**Risk:** `ALTER TABLE ... MODIFY COLUMN` on a large table acquires `ACCESS EXCLUSIVE` lock. Although making columns nullable is generally fast in Postgres (it's a catalog change, not a rewrite), the lock still blocks reads during the operation. On Somnia's very large `internal_transactions` table, even brief locks can cause queuing.

**Recommendation:** Monitor replication lag. Should be fast (metadata-only change in modern Postgres) but lock duration depends on concurrent activity.

---

### `20260213092943_add_internal_transactions_pk_not_null_constraint.exs`
**Operation:** Adds two `NOT NULL` CHECK constraints on `internal_transactions` with `validate: false`.

**Risk:** `validate: false` means constraint is added without scanning existing rows (safe for large tables). However, each `CREATE CONSTRAINT` still acquires a brief lock on the table. Two constraints = two lock acquisitions.

**Recommendation:** Low real risk given `validate: false`, but note these constraints will not be validated for existing rows.

---

### `20260220073239_alter_multichain_search_db_export_balances_queue_id_to_bigint.exs`
**Operation:** `ALTER TABLE ... ALTER COLUMN id TYPE bigint` + `VACUUM FULL` (conditional, only if <10k rows).

**Risk:** `ALTER COLUMN TYPE` is a full table rewrite with `ACCESS EXCLUSIVE` lock if the table has rows. The migration guards against this with a row count check (skips if ≥10k rows). `VACUUM FULL` also locks exclusively but is also conditional. The `@disable_ddl_transaction true` flag is set correctly.

**Recommendation:** Safe if the queue is empty at migration time. Verify queue is drained before deploying.

---

## 🟢 Safe

| Migration | Operation | Notes |
|---|---|---|
| `20260107090004_alter_contract_verification_status_table.exs` | RENAME TABLE + RENAME INDEX + RENAME COLUMN on `contract_verification_status` | Small table, metadata-only operations |
| `20260128120316_drop_internal_transactions_zero_value_delete_queue.exs` | DROP TABLE `internal_transactions_zero_value_delete_queue` | Small queue table, safe drop |
| `20260128160608_add_current_token_balance_retry_fields.exs` | ADD COLUMN (nullable smallint + utc_datetime) to `address_current_token_balances` | Adding nullable columns is a metadata-only op in Postgres 11+ |
| `20260217131711_reset_token_transfer_block_consensus_migration.exs` | DELETE FROM `migrations_status` (single row) | Trivial |
| `20260114143222_re_run_sanitize_incorrect_nft_migration.exs` | UPDATE `migrations_status` (single row) | Trivial |
| `20260121084059_reset_tokens_extended_skip_metadata.exs` | UPDATE `tokens` — resets `skip_metadata` to NULL where certain conditions met | Could affect many rows on large tokens table. Runs as background migrator, not DDL. Low lock risk but could be slow. |
| `20260220073231/73248/73250_vacuum_full_multichain_search_db_*.exs` | VACUUM FULL on multichain queue tables (conditional, <10k rows) | Safe if queues are small; skipped automatically if not |

---

## Recommended Deployment Order

1. Deploy during a low-traffic window
2. Ensure `multichain_search_db_*` queues are drained before migration
3. Watch replication lag during:
   - `20250812000000` (drop NOT NULL on internal_transactions)
   - `20250908062439` (add call_type_enum to internal_transactions)
   - `20250915135943` (add error_id + transaction_errors table)
4. After migration, monitor `internal_transactions` table health
