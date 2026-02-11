#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------------------------------- #
# test-build.sh — Local Docker build & smoke-test for Blockscout after rollout
# --------------------------------------------------------------------------- #
# Usage:
#   ./scripts/test-build.sh              # full build + test
#   ./scripts/test-build.sh --skip-build # retest with existing images
#   ./scripts/test-build.sh --keep       # leave containers running after test
# --------------------------------------------------------------------------- #

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.test.yml"

# Image names
IMG_API="blockscout-test-api"
IMG_INDEXER="blockscout-test-indexer"

# Flags
SKIP_BUILD=false
KEEP=false

for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=true ;;
    --keep)       KEEP=true ;;
    *)            echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

# ---- Colours --------------------------------------------------------------- #
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# ---- Version from mix.exs ------------------------------------------------- #
VERSION=$(grep -m1 'version:' "$PROJECT_ROOT/mix.exs" | sed 's/.*"\(.*\)".*/\1/')
info "Detected project version: $VERSION"

# ---- Shared env vars ------------------------------------------------------- #
SECRET_KEY_BASE=$(openssl rand -base64 48 | tr -d '\n')

COMMON_ENV=(
  -e "DATABASE_URL=postgresql://blockscout:testpassword@localhost:7433/blockscout_test"
  -e "ETHEREUM_JSONRPC_VARIANT=geth"
  -e "ETHEREUM_JSONRPC_HTTP_URL=http://localhost:8545/"
  -e "ETHEREUM_JSONRPC_TRACE_URL=http://localhost:8545/"
  -e "SECRET_KEY_BASE=$SECRET_KEY_BASE"
  -e "POOL_SIZE=10"
  -e "POOL_SIZE_API=5"
  -e "ECTO_USE_SSL=false"
  -e "COIN=SMN"
  -e "COIN_NAME=Somnia"
  -e "CHAIN_ID=50312"
  -e "DISABLE_MARKET=true"
  -e "HEART_BEAT_TIMEOUT=30"
  -e "API_V2_ENABLED=true"
  -e "ACCOUNT_ENABLED=false"
  -e "DISABLE_FILE_LOGGING=true"
)

# ---- Cleanup trap ---------------------------------------------------------- #
CONTAINERS_TO_CLEAN=()

cleanup() {
  if [ "$KEEP" = true ]; then
    warn "Keeping containers running (--keep). Clean up manually:"
    warn "  docker compose -f $COMPOSE_FILE down"
    for c in "${CONTAINERS_TO_CLEAN[@]:-}"; do
      [ -n "$c" ] && warn "  docker rm -f $c"
    done
    return
  fi

  info "Cleaning up..."
  for c in "${CONTAINERS_TO_CLEAN[@]:-}"; do
    [ -n "$c" ] && docker rm -f "$c" 2>/dev/null || true
  done
  docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# ---- Step 1: Build images ------------------------------------------------- #
COMMON_BUILD_ARGS=(
  --build-arg "BLOCKSCOUT_VERSION=v${VERSION}"
  --build-arg "RELEASE_VERSION=${VERSION}"
  --build-arg "DISABLE_WEBAPP=true"
  --build-arg "ADMIN_PANEL_ENABLED=false"
  --build-arg "CACHE_EXCHANGE_RATES_PERIOD="
  --build-arg "CACHE_TOTAL_GAS_USAGE_COUNTER_ENABLED=true"
  --build-arg "DECODE_NOT_A_CONTRACT_CALLS=false"
  --build-arg "MIXPANEL_URL="
  --build-arg "MIXPANEL_TOKEN="
  --build-arg "AMPLITUDE_URL="
  --build-arg "AMPLITUDE_API_KEY="
  --build-arg "CACHE_ADDRESS_WITH_BALANCES_UPDATE_INTERVAL="
)

if [ "$SKIP_BUILD" = false ]; then
  info "Building API image ($IMG_API)..."
  docker build \
    -f "$PROJECT_ROOT/docker/Dockerfile" \
    "${COMMON_BUILD_ARGS[@]}" \
    --build-arg "DISABLE_INDEXER=true" \
    --build-arg "API_V1_READ_METHODS_DISABLED=false" \
    --build-arg "API_V1_WRITE_METHODS_DISABLED=false" \
    -t "$IMG_API" \
    "$PROJECT_ROOT"

  if [ $? -eq 0 ]; then
    pass "API image built"
  else
    fail "API image build failed"
    exit 1
  fi

  info "Building Indexer image ($IMG_INDEXER)..."
  docker build \
    -f "$PROJECT_ROOT/docker/Dockerfile" \
    "${COMMON_BUILD_ARGS[@]}" \
    --build-arg "DISABLE_API=true" \
    --build-arg "API_V1_READ_METHODS_DISABLED=true" \
    --build-arg "API_V1_WRITE_METHODS_DISABLED=true" \
    -t "$IMG_INDEXER" \
    "$PROJECT_ROOT"

  if [ $? -eq 0 ]; then
    pass "Indexer image built"
  else
    fail "Indexer image build failed"
    exit 1
  fi
else
  info "Skipping build (--skip-build)"
  # Verify images exist
  docker image inspect "$IMG_API" >/dev/null 2>&1 || { fail "Image $IMG_API not found"; exit 1; }
  docker image inspect "$IMG_INDEXER" >/dev/null 2>&1 || { fail "Image $IMG_INDEXER not found"; exit 1; }
  pass "Existing images found"
fi

# ---- Step 2: Start infrastructure ----------------------------------------- #
info "Starting PostgreSQL and Redis..."
docker compose -f "$COMPOSE_FILE" up -d

info "Waiting for PostgreSQL to be ready..."
RETRIES=30
until docker compose -f "$COMPOSE_FILE" exec -T db pg_isready -U blockscout -d blockscout_test >/dev/null 2>&1; do
  RETRIES=$((RETRIES - 1))
  if [ "$RETRIES" -le 0 ]; then
    fail "PostgreSQL did not become ready in time"
    exit 1
  fi
  sleep 2
done
pass "PostgreSQL is ready"

# ---- Step 3: Run migrations ----------------------------------------------- #
info "Running database migrations..."
MIGRATE_CONTAINER="blockscout-test-migrate"
CONTAINERS_TO_CLEAN+=("$MIGRATE_CONTAINER")

docker run --rm --name "$MIGRATE_CONTAINER" \
  --network=host \
  "${COMMON_ENV[@]}" \
  -e "DISABLE_INDEXER=true" \
  -e "DISABLE_API=true" \
  "$IMG_API" \
  bin/blockscout eval "Elixir.Explorer.ReleaseTasks.create_and_migrate()"

if [ $? -eq 0 ]; then
  pass "Migrations completed"
else
  fail "Migrations failed"
  exit 1
fi

# ---- Step 4: Start indexer ------------------------------------------------ #
info "Starting indexer container..."
INDEXER_CONTAINER="blockscout-test-indexer"
CONTAINERS_TO_CLEAN+=("$INDEXER_CONTAINER")

docker run -d --name "$INDEXER_CONTAINER" \
  --network=host \
  "${COMMON_ENV[@]}" \
  -e "DISABLE_INDEXER=false" \
  -e "DISABLE_API=true" \
  -e "PORT=4001" \
  -e "RELEASE_NODE=indexer@127.0.0.1" \
  -e "RELEASE_DISTRIBUTION=name" \
  -e "RELEASE_COOKIE=test_cookie" \
  "$IMG_INDEXER" \
  bin/blockscout start

info "Waiting for indexer to start (20s)..."
sleep 20

if docker inspect "$INDEXER_CONTAINER" --format='{{.State.Running}}' 2>/dev/null | grep -q "true"; then
  # Check logs for obvious crash signals
  if docker logs "$INDEXER_CONTAINER" 2>&1 | grep -qi "** (EXIT\|** (RuntimeError\|** (ArgumentError\|could not compile"; then
    warn "Indexer is running but logs contain errors:"
    docker logs "$INDEXER_CONTAINER" 2>&1 | grep -i "** (" | head -5
    fail "Indexer started with errors"
    exit 1
  fi
  pass "Indexer is running"
else
  fail "Indexer container is not running"
  docker logs "$INDEXER_CONTAINER" 2>&1 | tail -30
  exit 1
fi

# ---- Step 5: Start API ---------------------------------------------------- #
info "Starting API container..."
API_CONTAINER="blockscout-test-api"
CONTAINERS_TO_CLEAN+=("$API_CONTAINER")

docker run -d --name "$API_CONTAINER" \
  --network=host \
  "${COMMON_ENV[@]}" \
  -e "DISABLE_INDEXER=true" \
  -e "DISABLE_API=false" \
  -e "PORT=4000" \
  -e "RELEASE_NODE=api@127.0.0.1" \
  -e "RELEASE_DISTRIBUTION=name" \
  -e "RELEASE_COOKIE=test_cookie" \
  "$IMG_API" \
  bin/blockscout start

info "Waiting for API to become available..."
RETRIES=30
API_READY=false
while [ "$RETRIES" -gt 0 ]; do
  if curl -sf http://localhost:4000/api/v2/stats >/dev/null 2>&1; then
    API_READY=true
    break
  fi
  RETRIES=$((RETRIES - 1))
  sleep 3
done

if [ "$API_READY" = false ]; then
  fail "API did not become available"
  docker logs "$API_CONTAINER" 2>&1 | tail -40
  exit 1
fi
pass "API is responding"

# Verify specific endpoints
info "Checking API endpoints..."

HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' http://localhost:4000/api/v2/stats)
if [ "$HTTP_CODE" = "200" ]; then
  pass "GET /api/v2/stats -> 200"
else
  fail "GET /api/v2/stats -> $HTTP_CODE"
  exit 1
fi

HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' http://localhost:4000/api/v2/blocks)
if [ "$HTTP_CODE" = "200" ]; then
  pass "GET /api/v2/blocks -> 200"
else
  fail "GET /api/v2/blocks -> $HTTP_CODE"
  exit 1
fi

# ---- Done ----------------------------------------------------------------- #
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} All checks passed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
info "Version: $VERSION"
info "API image: $IMG_API"
info "Indexer image: $IMG_INDEXER"
