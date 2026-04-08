#!/usr/bin/env bash
# ============================================================
#  run_demo.sh — Full Cassandra Product-Reviews Demo Runner
#  Runs Member 1 + Member 2 scripts against a live Docker cluster
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

CQLSH="docker exec -i cassandra-node1 cqlsh"
NODETOOL="docker exec cassandra-node1 nodetool"

banner() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════${RESET}"; echo -e "${BOLD}${CYAN}  $1${RESET}"; echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${RESET}\n"; }
ok()     { echo -e "${GREEN}✔  $1${RESET}"; }
info()   { echo -e "${YELLOW}ℹ  $1${RESET}"; }
err()    { echo -e "${RED}✘  $1${RESET}"; }

# ── Wait for Cassandra to accept CQL connections ─────────────
wait_for_cassandra() {
    banner "Waiting for Cassandra node1 to be ready..."
    local retries=30
    until docker exec cassandra-node1 cqlsh -e "DESCRIBE CLUSTER" &>/dev/null; do
        retries=$((retries - 1))
        if [[ $retries -eq 0 ]]; then
            err "Timed out waiting for Cassandra."
            exit 1
        fi
        info "Not ready yet — retrying in 10s ($retries attempts left)..."
        sleep 10
    done
    ok "Cassandra is accepting CQL connections."
}

# ── Execute a CQL file ────────────────────────────────────────
run_cql() {
    local label="$1"; local file="$2"
    info "Running: $label"
    docker exec -i cassandra-node1 cqlsh < "$file"
    ok "Done: $label"
}

# ═════════════════════════════════════════════════════════════
#  MAIN
# ═════════════════════════════════════════════════════════════

banner "Product Review Storage & Retrieval — NoSQL + Cassandra"
echo -e "  Cluster : ReviewCluster (3 nodes, dc1, RF=3)"
echo -e "  Image   : cassandra:4.1\n"

# 1. Start cluster
banner "Step 1 — Starting 3-node Cassandra cluster"
docker compose up -d
ok "Docker containers launched."

wait_for_cassandra

# 2. Cluster topology
banner "Step 2 — Cluster topology (nodetool status)"
$NODETOOL status

# ─────────────────────────────────────────────────────────────
banner "MEMBER 1 — Architecture & Storage"
# ─────────────────────────────────────────────────────────────

# 3. Schema
banner "Step 3 — Create keyspace & schema (Member 1)"
run_cql "01_schema.cql" scripts/01_schema.cql

info "Inspecting partition key strategy..."
docker exec -i cassandra-node1 cqlsh <<'EOF'
USE product_store;
DESCRIBE TABLE product_reviews;
EOF

# 4. Insert data
banner "Step 4 — Insert sample reviews (Member 1: CQL DML demo)"
run_cql "02_insert_data.cql" scripts/02_insert_data.cql

# ─────────────────────────────────────────────────────────────
banner "MEMBER 2 — Retrieval & Scalability"
# ─────────────────────────────────────────────────────────────

# 5. Indexes + Queries
banner "Step 5 — Create indexes & materialized view (Member 2)"
run_cql "03_indexes_and_queries.cql" scripts/03_indexes_and_queries.cql

# 6. Scalability: token distribution
banner "Step 6 — Scalability inspection"
info "Ring token distribution:"
$NODETOOL ring | head -20

info "Gossip / node info:"
$NODETOOL info

info "Compaction stats:"
$NODETOOL compactionstats 2>/dev/null || echo "(no compactions running)"

info "Replication: check token ranges for a product partition"
docker exec -i cassandra-node1 nodetool getendpoints product_store product_reviews \
    "11111111-1111-1111-1111-111111111111" 2>/dev/null \
    && ok "Replica endpoints shown above" \
    || info "(getendpoints skipped — schema not yet propagated)"

# 7. Summary
banner "Demo Complete ✓"
echo -e "  Keyspace  : product_store"
echo -e "  Tables    : product_reviews, products, product_review_counts, temp_reviews"
echo -e "  MV        : reviews_by_rating"
echo -e "  Indexes   : idx_rating, idx_verified, idx_review_text_sasi (SASI)"
echo -e ""
echo -e "  Connect manually:  docker exec -it cassandra-node1 cqlsh"
echo -e "  Teardown:          docker compose down -v"
echo ""
