-- ============================================================
--  MEMBER 1 — Architecture & Storage
--  Script: 01_schema.cql
--  Purpose: Keyspace creation + product_reviews table design
-- ============================================================

-- ── 1. Keyspace ─────────────────────────────────────────────
--  NetworkTopologyStrategy is production-ready; SimpleStrategy
--  works for a single-DC lab environment.
--  replication_factor: 3 means every row lives on 3 nodes.
-- ────────────────────────────────────────────────────────────
CREATE KEYSPACE IF NOT EXISTS product_store
    WITH replication = {
        'class'              : 'NetworkTopologyStrategy',
        'dc1'                : 3
    }
    AND durable_writes = true;

USE product_store;

-- ── 2. Core Reviews Table ────────────────────────────────────
--  PRIMARY KEY design rationale
--    Partition key : product_id  → all reviews for a product
--                                  live on the same node(s)
--    Clustering    : review_date → rows within a partition are
--                                  physically sorted newest first
--                  + review_id  → unique row identifier
--
--  This means the common query "give me the latest N reviews
--  for product X" is a single-partition read — no scatter/gather.
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS product_reviews (
    product_id   UUID,
    review_date  TIMESTAMP,
    review_id    UUID,
    user_id      UUID,
    rating       INT,
    review_text  TEXT,
    helpful_votes INT,
    verified_purchase BOOLEAN,
    PRIMARY KEY (product_id, review_date, review_id)
) WITH CLUSTERING ORDER BY (review_date DESC, review_id ASC)
  AND comment = 'Wide-row review store; one partition per product'
  AND gc_grace_seconds    = 864000     -- 10 days tombstone grace
  AND compaction = {
      'class'                   : 'TimeWindowCompactionStrategy',
      'compaction_window_unit'   : 'DAYS',
      'compaction_window_size'   : '7'
  };

-- ── 3. Product Catalogue (denormalised lookup) ───────────────
--  Cassandra best practice: duplicate data to avoid joins.
--  Store product metadata alongside reviews when needed.
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS products (
    product_id   UUID PRIMARY KEY,
    product_name TEXT,
    category     TEXT,
    avg_rating   FLOAT,
    review_count COUNTER
);

-- Note: COUNTER tables cannot mix counter and non-counter cols.
-- Use a separate table for the counter column.
CREATE TABLE IF NOT EXISTS product_review_counts (
    product_id   UUID PRIMARY KEY,
    review_count COUNTER
);

-- ── 4. TTL demo table (Member 2 will query this) ─────────────
CREATE TABLE IF NOT EXISTS temp_reviews (
    product_id  UUID,
    review_id   UUID,
    review_text TEXT,
    PRIMARY KEY (product_id, review_id)
);

DESCRIBE TABLES;
