# Product Review Storage & Retrieval — NoSQL + Cassandra
> Team of 2 · Docker-based 3-node cluster

---

## Project Overview

This project implements a **product review system** using Apache Cassandra, demonstrating how NoSQL handles large-scale, write-heavy, unstructured review data that relational databases struggle with.

**Why Cassandra for product reviews?**

| Challenge | SQL Problem | Cassandra Solution |
|---|---|---|
| Millions of concurrent writes | Lock contention, slow B-tree inserts | Log-structured storage, write-optimised LSM tree |
| Reads by product (hot rows) | Table scans / joins | Partition key ensures co-location |
| Global distribution | Replication lag, single master | Leaderless, tunable consistency |
| Schema evolution | ALTER TABLE locks | Add columns online, flexible types |
| Time-series ordering | No physical ordering | Clustering columns define on-disk sort |

---

## Architecture

```
User Request
     │
     ▼
  REST API  (your application layer)
     │
     ▼
  Cassandra Coordinator Node  (any node can be coordinator)
     │
     ├─── Node 1 (seed)  ─── vnodes: token ranges 1..85
     ├─── Node 2          ─── vnodes: token ranges 86..170
     └─── Node 3          ─── vnodes: token ranges 171..256
           │
     Consistent Hashing Ring (256 vnodes, RF=3)
     Every partition replicated to 3 nodes
```

**Key concepts:**
- **Consistent hashing** — `product_id` is hashed to a token; that token falls in a node's range
- **Replication factor 3** — each partition lives on 3 nodes; survive 1 node failure with no data loss
- **Eventual consistency** — `QUORUM` reads/writes ensure you read what you last wrote
- **Vnodes** — each physical node owns 256 virtual token ranges for even load distribution

---

## Repository Layout

```
cassandra-reviews/
├── docker-compose.yml          # 3-node Cassandra cluster
├── run_demo.sh                 # One-shot demo runner
└── scripts/
    ├── 01_schema.cql           # Member 1 — Keyspace + table design
    ├── 02_insert_data.cql      # Member 1 — CQL INSERT demo
    └── 03_indexes_and_queries.cql  # Member 2 — Indexes + query patterns
```

---

## Quick Start

### Prerequisites
- Docker ≥ 24 and Docker Compose v2
- ~3 GB RAM free (512 MB heap × 3 nodes)

### Run everything
```bash
chmod +x run_demo.sh
./run_demo.sh
```

This will:
1. Start a 3-node Cassandra cluster
2. Wait for the cluster to be healthy
3. Run Member 1's schema + insert scripts
4. Run Member 2's index + query scripts
5. Print cluster topology and scalability stats

### Connect manually
```bash
docker exec -it cassandra-node1 cqlsh
```

### Teardown
```bash
docker compose down -v   # -v removes data volumes
```

---

## Member 1 — Architecture & Storage

### CAP Theorem & Cassandra's choice
Cassandra chooses **AP** (Availability + Partition Tolerance). It trades strong consistency for always-on writes. For product reviews this is ideal — a slightly stale rating is acceptable; a failed write is not.

**ACID vs BASE:**
- SQL databases enforce ACID (Atomicity, Consistency, Isolation, Durability) — great for financial transactions
- Cassandra uses BASE (Basically Available, Soft state, Eventually consistent) — great for user-generated content at scale

### Data Model Design

#### Schema
```cql
CREATE TABLE product_reviews (
    product_id        UUID,
    review_date       TIMESTAMP,
    review_id         UUID,
    user_id           UUID,
    rating            INT,
    review_text       TEXT,
    helpful_votes     INT,
    verified_purchase BOOLEAN,
    PRIMARY KEY (product_id, review_date, review_id)
) WITH CLUSTERING ORDER BY (review_date DESC, review_id ASC)
  AND compaction = { 'class': 'TimeWindowCompactionStrategy', ... };
```

#### Why this primary key?

```
PRIMARY KEY (product_id, review_date, review_id)
             ──────────  ───────────  ─────────
             Partition   Clustering   Unique row
             key         column 1     identifier
```

- **Partition key `product_id`**: All reviews for one product hash to the same partition → same set of nodes. The most common query ("show reviews for product X") never needs cross-node coordination.
- **Clustering `review_date DESC`**: Rows within a partition are physically sorted newest-first on disk. `LIMIT 10` returns the 10 most recent reviews with a single sequential disk read — no sort step.
- **Clustering `review_id`**: Breaks ties when two reviews land at the exact same millisecond, ensuring row uniqueness.

#### Denormalisation
Cassandra has no joins. Data is duplicated to serve each query pattern efficiently — a deliberate design choice, not a limitation.

#### TimeWindowCompactionStrategy
Chosen because review data is time-series: old SSTables (older than 7 days) are never rewritten together with new ones, minimising write amplification for append-heavy workloads.

### CQL DML Quick Reference

```cql
-- Create keyspace
CREATE KEYSPACE product_store
    WITH replication = {'class':'NetworkTopologyStrategy','dc1':3};

-- Insert a review
INSERT INTO product_reviews (product_id, review_date, review_id, ...)
VALUES (uuid(), toTimestamp(now()), uuid(), ...);

-- Insert with TTL (auto-delete after 30 days)
INSERT INTO product_reviews (...) VALUES (...) USING TTL 2592000;

-- Select all reviews for a product
SELECT * FROM product_reviews WHERE product_id = <uuid>;
```

---

## Member 2 — Retrieval & Scalability

### Indexing in Cassandra

| Index Type | How it works | Best for |
|---|---|---|
| **Primary index** | Partition key → node routing via consistent hash | Exact match on `product_id` |
| **Secondary index** | Local index on each node; coordinator fans out | Low-cardinality columns like `rating` (1-5) |
| **SASI index** | Per-SSTable inverted index; supports LIKE/prefix | Full-text search on `review_text` |
| **Materialized View** | Server-maintained denormalised copy | Alternative access patterns without ALLOW FILTERING |

### Query Patterns

#### Q1 — All reviews for a product (primary pattern)
```cql
SELECT * FROM product_reviews
 WHERE product_id = 11111111-1111-1111-1111-111111111111;
-- Single partition read. O(1) node lookups. ✓
```

#### Q2 — Latest N reviews
```cql
SELECT * FROM product_reviews
 WHERE product_id = <uuid>
 LIMIT 10;
-- Cluster key DESC + LIMIT = head scan. Very fast. ✓
```

#### Q3 — Filter by rating (secondary index)
```cql
SELECT * FROM product_reviews WHERE rating = 5;
-- Cross-partition; coordinator queries all nodes in parallel.
-- Acceptable for low-cardinality (1-5 values only). ✓
```

#### Q4 — Top-rated via Materialized View (preferred)
```cql
SELECT * FROM reviews_by_rating WHERE rating = 5 LIMIT 10;
-- MV is a separate physical table; single partition. Much faster. ✓
```

#### Q5 — Full-text search via SASI
```cql
SELECT * FROM product_reviews WHERE review_text LIKE '%sound%';
-- SASI CONTAINS mode; tokenises and case-folds. ✓
```

#### Q6 — Date range slice
```cql
SELECT * FROM product_reviews
 WHERE product_id = <uuid>
   AND review_date >= '2024-11-01' AND review_date <= '2024-12-31';
-- Clustering column range = sequential scan within one partition. ✓
```

### ALLOW FILTERING — When to use, when to avoid

```cql
-- ✗ Avoid at scale — full cluster scan
SELECT * FROM product_reviews
 WHERE verified_purchase = true ALLOW FILTERING;

-- ✓ Use a secondary index instead for non-PK column predicates
CREATE INDEX idx_verified ON product_reviews (verified_purchase);
SELECT * FROM product_reviews WHERE verified_purchase = true;
```

**Rule of thumb:** If a query requires `ALLOW FILTERING`, create an index or a materialized view so the coordinator can route intelligently.

### Scalability Concepts

#### Consistent Hashing
Each `product_id` UUID is run through a hash function (Murmur3) to produce a 64-bit token. That token falls in one of 256 vnode ranges owned by a physical node. When you add a node, only a fraction of ranges move — no full resharding.

#### Replication Factor
With `RF=3` and `NetworkTopologyStrategy`, every partition is stored on 3 nodes. If one goes down, reads and writes continue seamlessly with RF=3, QUORUM consistency (`(3/2)+1 = 2` nodes must agree).

#### Eventual Consistency
Cassandra uses **read repair** and **hinted handoff** to reconcile replicas that fell behind. For product reviews, a user seeing a rating that's 100ms stale is perfectly acceptable.

#### Blob Storage & TTL
Large assets (images, videos) are stored in S3/GCS, with their URLs in Cassandra. Cassandra's `TTL` column attribute auto-expires temporary or cached review drafts without manual cleanup jobs.

#### Compaction Strategies
- **STCS** (SizeTieredCompactionStrategy) — default; good for write-heavy workloads
- **TWCS** (TimeWindowCompactionStrategy) — ideal for time-series data like reviews; groups SSTables by time window, rarely rewrites old data
- **LCS** (LeveledCompactionStrategy) — optimised for read-heavy workloads; trades more I/O for smaller, non-overlapping SSTables

---

## Shared — SQL vs NoSQL Comparison

| Feature | PostgreSQL | Cassandra |
|---|---|---|
| Data model | Normalised tables + joins | Denormalised, query-driven |
| Write speed | ~10K writes/sec (single node) | ~1M writes/sec (3 nodes) |
| Horizontal scale | Read replicas (complex) | Native, linear scaling |
| Schema changes | Locks table (can be disruptive) | Online column additions |
| Consistency | Strong (ACID) | Tunable (ONE → QUORUM → ALL) |
| Full-text search | `pg_trgm`, `tsquery` | SASI index / Apache Solr integration |
| Best for | Financial records, relational data | High-write, distributed, time-series |

---

## Future Scope

- **Apache Solr integration** via [DataStax Search](https://docs.datastax.com/en/dse/6.8/dse-dev/datastax_enterprise/search/searchTOC.html) for full-text search across all reviews
- **Apache Kafka** as a write buffer to handle review ingestion spikes
- **Spark + Cassandra connector** for batch analytics (average rating per category)
- **CDC (Change Data Capture)** to stream review events to downstream systems
