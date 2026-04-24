# Release Changes: v9.3.2 → v10.2.6

## New ENV Variables

| Variable | Default | Description | Applications |
|---|---|---|---|
| `MIGRATION_DELETE_ZERO_VALUE_INTERNAL_TRANSACTIONS_STORAGE_PERIOD` | `30d` | Period for which recent zero-value calls won't be deleted in delete zero-value calls migration | Indexer |
| `BLOCK_MINER_GETS_BURNT_FEES` | `false` | If `true`, burnt fees are added to block miner profit and displayed as zero in UI | API |
| `UNIVERSAL_PROXY_CONFIG` | (empty) | JSON-encoded configuration string for the universal proxy | API |
| `MIGRATION_EMPTY_INTERNAL_TRANSACTIONS_DATA_BATCH_SIZE` | `1000` | Batch size for clearing internal transaction data | Indexer |
| `MIGRATION_EMPTY_INTERNAL_TRANSACTIONS_DATA_CONCURRENCY` | `1` | Parallel batches for clearing internal transaction data | Indexer |
| `MIGRATION_EMPTY_INTERNAL_TRANSACTIONS_DATA_TIMEOUT` | `0` | Timeout between clearing internal transaction data batches | Indexer |
| `CACHE_PENDING_OPERATIONS_COUNT_PERIOD` | `5m` | Interval to recalculate total pending operations count | API, Indexer |
| `ACCOUNT_DYNAMIC_ENV_ID` | (empty) | Dynamic Environment ID from app.dynamic.xyz dashboard | API |
| `INDEXER_OPTIMISM_L1_BATCH_EIGENDA_BLOBS_API_URL` | (empty) | URL to DA indexer supporting EigenDA layer | Indexer |
| `INDEXER_OPTIMISM_L1_BATCH_EIGENDA_PROXY_BASE_URL` | (empty) | URL to EigenDA proxy node | Indexer |
| `INDEXER_ARBITRUM_MESSAGES_TRACKING_FAILURE_THRESHOLD` | `10m` | Time threshold for L1 message tracking task failure | Indexer |
| `INDEXER_ARBITRUM_MISSED_MESSAGE_IDS_RANGE` | `10000` | Message ID range size for discovering missing L1-to-L2 messages | Indexer |
| `INDEXER_CURRENT_TOKEN_BALANCES_BATCH_SIZE` | `100` | Batch size for current token balances fetcher | Indexer |
| `INDEXER_CURRENT_TOKEN_BALANCES_CONCURRENCY` | `10` | Concurrency for current token balances fetcher | Indexer |
| `ACCOUNT_SENDGRID_OTP_TEMPLATE` | (empty) | Sendgrid email OTP template for email login (Keycloak) | API |
| `ACCOUNT_KEYCLOAK_DOMAIN` | (empty) | Domain for Keycloak | API |
| `ACCOUNT_KEYCLOAK_REALM` | (empty) | Realm for Keycloak | API |
| `ACCOUNT_KEYCLOAK_CLIENT_ID` | (empty) | Keycloak client ID | API |
| `ACCOUNT_KEYCLOAK_CLIENT_SECRET` | (empty) | Keycloak client secret | API |
| `ACCOUNT_KEYCLOAK_EMAIL_WEBHOOK_URL` | (empty) | URL where new email users are reported (Keycloak) | API |
| `INDEXER_TOKEN_TRANSFER_BLOCK_CONSENSUS_SANITIZER_INTERVAL` | `20m` | Interval for token transfer block consensus sanitizer | Indexer |
| `ETHEREUM_JSONRPC_RECEIPTS_BY_BLOCK` | `false` | If `true`, fetch transaction receipts by block instead of per transaction | API, Indexer |
| `ETHEREUM_JSONRPC_MAX_RECEIPTS_BY_BLOCK` | `1000` | Max transactions in block for which receipts are fetched by block | API, Indexer |
| `MUD_INDEXER_ENABLED` | (empty) | Enables MUD indexer (new Dockerfile ARG) | API, Indexer |

## Deprecated ENV Variables

| Variable | Replaced By | Deprecated In |
|---|---|---|
| `MIGRATION_DELETE_ZERO_VALUE_INTERNAL_TRANSACTIONS_STORAGE_PERIOD_DAYS` | `MIGRATION_DELETE_ZERO_VALUE_INTERNAL_TRANSACTIONS_STORAGE_PERIOD` (time format) | v9.3.3 |
| `CACHE_PBO_COUNT_PERIOD` | `CACHE_PENDING_OPERATIONS_COUNT_PERIOD` | v10.0.0 |

## Breaking Changes

- **Internal transaction re-architecture (v10.0.0):** Internal transactions now use a call-type enum, error dictionary, and normalization format. Custom code that parses internal transaction data may need updates. The re-architecture also includes heavy DB migrations (see `migration-risks.md`).
- **`block_index` → `transaction_index` + `index` refactor (v10.0.0):** Internal transaction indexing logic was refactored from `block_index` to `(transaction_index, index)` composite. This is load-bearing for the Somnia custom `feat: fetching subsets of internal transactions` change — **this commit must be carefully re-verified post-merge**.
- **DeleteZeroValueInternalTransactions behaviour (v9.3.3):** The ZeroValueDeleteQueue was replaced with filtering on import. The Somnia custom `feat: filter old internal transactions error from indexing` commit may interact with this change.
- **Current token balances moved to separate fetcher (v10.0.0):** New fetcher with its own concurrency/batch settings (`INDEXER_CURRENT_TOKEN_BALANCES_*`).
- **`CACHE_PBO_COUNT_PERIOD` removed** — replace with `CACHE_PENDING_OPERATIONS_COUNT_PERIOD` in any deployment config.
- **`MissingRangesManipulator` disabled (v10.0.0)** — if Somnia relied on this, it no longer runs by default.

## Build Changes

| Item | Old | New |
|---|---|---|
| `mix.exs` version | `9.3.2` | `10.2.6` |
| `prometheus_ex` | `~> 5.0.0` | `~> 5.1.0` |
| `tesla` | `~> 1.15.3` | `~> 1.16.0` |
| `ex_doc` | `~> 0.39.1` | `~> 0.40.1` |
| Dockerfile ARG | — | `MUD_INDEXER_ENABLED` added to both build stages |

## New Features (Awareness)

- **ERC-7984 Confidential Tokens** (v10.0.0)
- **Dynamic auth provider** support (v10.0.0) — `ACCOUNT_DYNAMIC_ENV_ID`
- **Keycloak integration** (v10.1.0) — 6 new env vars
- **Universal proxy config** (v10.0.0) — `UNIVERSAL_PROXY_CONFIG`
- **Distributed cache** (v10.0.0)
- **Fetch receipts by block** (v10.2.0) — potential performance improvement for Somnia's high-TPS chain

## Action Items

- [ ] Update deployment config: replace `CACHE_PBO_COUNT_PERIOD` with `CACHE_PENDING_OPERATIONS_COUNT_PERIOD`
- [ ] Replace `MIGRATION_DELETE_ZERO_VALUE_INTERNAL_TRANSACTIONS_STORAGE_PERIOD_DAYS` with `MIGRATION_DELETE_ZERO_VALUE_INTERNAL_TRANSACTIONS_STORAGE_PERIOD` (uses time format, e.g. `30d`)
- [ ] Consider enabling `ETHEREUM_JSONRPC_RECEIPTS_BY_BLOCK=true` — may reduce RPC call volume on Somnia's high-TPS chain
- [ ] Review the internal transaction re-architecture impact on the custom `feat: fetching subsets of internal transactions` commit
- [ ] Add `MUD_INDEXER_ENABLED` build ARG to CI `build-push.yml` (optional, can leave empty)
- [ ] Run migration risk assessment before applying to production (see `migration-risks.md`)
