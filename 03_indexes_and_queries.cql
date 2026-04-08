-- ============================================================
--  MEMBER 2 — Retrieval & Scalability
--  Script: 03_indexes_and_queries.cql
--  Purpose: Secondary indexes, materialized views, query patterns
-- ============================================================

USE product_store;

-- ════════════════════════════════════════════════════════════
--  PART A — INDEXING
-- ════════════════════════════════════════════════════════════

-- ── A1. Secondary Index on rating ───────────────────────────
--  Allows: SELECT ... WHERE rating = 5
--  Trade-off: read is cross-partition (coordinator fans out to
--  all nodes); works fine at low cardinality like rating 1-5.
-- ────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_rating
    ON product_reviews (rating);

-- ── A2. Secondary Index on verified_purchase ─────────────────
CREATE INDEX IF NOT EXISTS idx_verified
    ON product_reviews (verified_purchase);

-- ── A3. SASI index on review_text for prefix/contains search ─
--  SASI = SSTable Attached Secondary Index
--  Enables LIKE queries: WHERE review_text LIKE '%headphone%'
--  Must enable in cassandra.yaml; supported in Cassandra 3.4+
-- ────────────────────────────────────────────────────────────
CREATE CUSTOM INDEX IF NOT EXISTS idx_review_text_sasi
    ON product_reviews (review_text)
    USING 'org.apache.cassandra.index.sasi.SASIIndex'
    WITH OPTIONS = {
        'mode'             : 'CONTAINS',
        'analyzer_class'   : 'org.apache.cassandra.index.sasi.analyzer.StandardAnalyzer',
        'case_sensitive'   : 'false'
    };

-- ── A4. Materialized View — reviews by rating ────────────────
--  A MV is a server-side denormalised copy updated automatically.
--  Allows efficient "top-rated" queries without ALLOW FILTERING.
--
--  Rule: every primary-key column of base table MUST appear in
--  the MV PK; the new column (rating) becomes partition key.
-- ────────────────────────────────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS reviews_by_rating AS
    SELECT product_id, review_date, review_id,
           rating, user_id, review_text, helpful_votes
      FROM product_reviews
     WHERE product_id  IS NOT NULL
       AND review_date IS NOT NULL
       AND review_id   IS NOT NULL
       AND rating      IS NOT NULL
PRIMARY KEY (rating, product_id, review_date, review_id)
    WITH CLUSTERING ORDER BY (product_id ASC, review_date DESC, review_id ASC);


-- ════════════════════════════════════════════════════════════
--  PART B — QUERY PATTERNS
-- ════════════════════════════════════════════════════════════

-- ── B1. All reviews for a product (partition scan) ────────────
--  This is the PRIMARY access pattern — single partition read.
--  Extremely efficient; no index needed.
-- ────────────────────────────────────────────────────────────
SELECT product_id, review_date, rating, review_text
  FROM product_reviews
 WHERE product_id = 11111111-1111-1111-1111-111111111111;

-- ── B2. Latest 3 reviews for a product (LIMIT) ───────────────
--  CLUSTERING ORDER BY review_date DESC means newest rows are
--  physically first → LIMIT is effectively a top-N head scan.
-- ────────────────────────────────────────────────────────────
SELECT review_date, rating, review_text
  FROM product_reviews
 WHERE product_id = 11111111-1111-1111-1111-111111111111
 LIMIT 3;

-- ── B3. Filter by rating using secondary index ───────────────
--  Secondary index lookup — coordinator queries all nodes.
--  Acceptable here (low cardinality column, small result set).
-- ────────────────────────────────────────────────────────────
SELECT product_id, review_date, rating, review_text
  FROM product_reviews
 WHERE rating = 5;

-- ── B4. Top-rated reviews via Materialized View ───────────────
--  Single-partition read on MV — much faster than B3 at scale.
-- ────────────────────────────────────────────────────────────
SELECT product_id, review_date, review_text
  FROM reviews_by_rating
 WHERE rating = 5
 LIMIT 10;

-- ── B5. Reviews in a date range (clustering column slice) ─────
--  Clustering column comparisons are efficient within a partition.
-- ────────────────────────────────────────────────────────────
SELECT review_date, rating, review_text
  FROM product_reviews
 WHERE product_id = 11111111-1111-1111-1111-111111111111
   AND review_date >= '2024-11-01 00:00:00+0000'
   AND review_date <= '2024-12-31 23:59:59+0000';

-- ── B6. Full-text search via SASI ────────────────────────────
--  SASI CONTAINS mode tokenises text; supports partial matches.
-- ────────────────────────────────────────────────────────────
SELECT product_id, review_text, rating
  FROM product_reviews
 WHERE review_text LIKE '%sound%';

-- ── B7. ALLOW FILTERING demo (anti-pattern for large tables) ──
--  This works but scans ALL partitions. Shown to illustrate why
--  secondary indexes / MVs are preferred at scale.
-- ────────────────────────────────────────────────────────────
SELECT product_id, rating, review_text
  FROM product_reviews
 WHERE verified_purchase = true
 ALLOW FILTERING;

-- ── B8. Counter read ─────────────────────────────────────────
SELECT product_id, review_count
  FROM product_review_counts
 WHERE product_id = 11111111-1111-1111-1111-111111111111;

-- ── B9. TTL check on temp review ─────────────────────────────
--  TTL(column) returns remaining seconds; 0 = expired/no TTL.
SELECT product_id, review_text, TTL(review_text) AS remaining_ttl
  FROM temp_reviews
 WHERE product_id = 11111111-1111-1111-1111-111111111111;


-- ════════════════════════════════════════════════════════════
--  PART C — SCALABILITY INSPECTION (nodetool equivalents in CQL)
-- ════════════════════════════════════════════════════════════

-- Show token ranges (vnodes) and replication details:
SELECT peer, data_center, rack, tokens
  FROM system.peers;

-- Keyspace replication config:
SELECT keyspace_name, replication
  FROM system_schema.keyspaces
 WHERE keyspace_name = 'product_store';

-- Table metadata (compaction strategy, gc_grace, etc.):
SELECT table_name, compaction, gc_grace_seconds, bloom_filter_fp_chance
  FROM system_schema.tables
 WHERE keyspace_name = 'product_store';

-- Confirm all indexes and views:
SELECT index_name, kind, options
  FROM system_schema.indexes
 WHERE keyspace_name = 'product_store';

SELECT view_name, base_table_name
  FROM system_schema.views
 WHERE keyspace_name = 'product_store';
