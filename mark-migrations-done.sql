-- =============================================================================
-- Mark manually-executed migrations as done in Blockscout tracking tables.
--
-- Run this AFTER you have successfully executed each SQL block from
-- migration-scripts.txt. Only mark a migration if you confirmed it ran
-- without errors.
--
-- Usage:
--   psql -h <host> -U <user> -d blockscout -f mark-migrations-done.sql
--
-- Safe to run multiple times (idempotent via ON CONFLICT).
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Regular Ecto migrations → schema_migrations
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO schema_migrations (version, inserted_at)
VALUES
  -- 20250714093329_add_multichain_search_db_token_info_export_queue_table
  (20250714093329, NOW()),
  -- 20250718092418_refactor_proxy_implementations
  (20250718092418, NOW()),
  -- 20251115202635_drop_tokens_contract_address_hash_index
  (20251115202635, NOW()),
  -- 20251202092200_update_contract_methods_unique_index
  (20251202092200, NOW())
ON CONFLICT (version) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Background migrator → migrations_status
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO migrations_status (migration_name, status, meta, inserted_at, updated_at)
VALUES
  ('heavy_indexes_drop_token_instances_token_id_index', 'completed', '{}', NOW(), NOW())
ON CONFLICT (migration_name)
  DO UPDATE SET status     = 'completed',
                updated_at = NOW();

COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Verification queries
-- ─────────────────────────────────────────────────────────────────────────────

SELECT version, inserted_at
FROM schema_migrations
WHERE version IN (20250714093329, 20250718092418, 20251115202635, 20251202092200)
ORDER BY version;

SELECT migration_name, status, updated_at
FROM migrations_status
WHERE migration_name = 'heavy_indexes_drop_token_instances_token_id_index';
