-- ============================================================
--  MEMBER 1 — Architecture & Storage
--  Script: 02_insert_data.cql
--  Purpose: Insert sample product reviews to demo CQL DML
-- ============================================================

USE product_store;

-- ── Fixed UUIDs for reproducible demos ───────────────────────
--  product_id A = "Wireless Headphones Pro"
--  product_id B = "Mechanical Keyboard RGB"
--  product_id C = "USB-C Hub 7-in-1"

-- ── Product A reviews ────────────────────────────────────────
INSERT INTO product_reviews
    (product_id, review_date, review_id, user_id, rating, review_text, helpful_votes, verified_purchase)
VALUES (
    11111111-1111-1111-1111-111111111111,
    '2024-12-01 10:00:00+0000',
    uuid(), uuid(),
    5,
    'Absolutely love these headphones. Crystal-clear sound and ANC is fantastic.',
    42, true
);

INSERT INTO product_reviews
    (product_id, review_date, review_id, user_id, rating, review_text, helpful_votes, verified_purchase)
VALUES (
    11111111-1111-1111-1111-111111111111,
    '2024-11-20 14:30:00+0000',
    uuid(), uuid(),
    4,
    'Great build quality. Battery life could be better — gets ~18hrs not the advertised 30.',
    18, true
);

INSERT INTO product_reviews
    (product_id, review_date, review_id, user_id, rating, review_text, helpful_votes, verified_purchase)
VALUES (
    11111111-1111-1111-1111-111111111111,
    '2024-10-05 09:15:00+0000',
    uuid(), uuid(),
    2,
    'Bluetooth keeps dropping. Returned after a week. Very disappointed.',
    7, true
);

INSERT INTO product_reviews
    (product_id, review_date, review_id, user_id, rating, review_text, helpful_votes, verified_purchase)
VALUES (
    11111111-1111-1111-1111-111111111111,
    '2024-09-18 16:45:00+0000',
    uuid(), uuid(),
    5,
    'Best headphones I have ever owned. Worth every penny.',
    55, false
);

INSERT INTO product_reviews
    (product_id, review_date, review_id, user_id, rating, review_text, helpful_votes, verified_purchase)
VALUES (
    11111111-1111-1111-1111-111111111111,
    '2024-08-30 11:00:00+0000',
    uuid(), uuid(),
    3,
    'Decent sound, uncomfortable for long sessions. Ear cups too shallow.',
    12, true
);

-- ── Product B reviews ────────────────────────────────────────
INSERT INTO product_reviews
    (product_id, review_date, review_id, user_id, rating, review_text, helpful_votes, verified_purchase)
VALUES (
    22222222-2222-2222-2222-222222222222,
    '2024-12-10 08:00:00+0000',
    uuid(), uuid(),
    5,
    'Tactile feedback is superb. Clicky switches are loud but SO satisfying.',
    31, true
);

INSERT INTO product_reviews
    (product_id, review_date, review_id, user_id, rating, review_text, helpful_votes, verified_purchase)
VALUES (
    22222222-2222-2222-2222-222222222222,
    '2024-11-22 19:00:00+0000',
    uuid(), uuid(),
    4,
    'Solid build, RGB lighting is gorgeous. Software app is a bit clunky.',
    9, true
);

INSERT INTO product_reviews
    (product_id, review_date, review_id, user_id, rating, review_text, helpful_votes, verified_purchase)
VALUES (
    22222222-2222-2222-2222-222222222222,
    '2024-10-14 13:00:00+0000',
    uuid(), uuid(),
    1,
    'Key stopped working after 2 months. Customer support unhelpful.',
    3, true
);

-- ── Product C reviews ────────────────────────────────────────
INSERT INTO product_reviews
    (product_id, review_date, review_id, user_id, rating, review_text, helpful_votes, verified_purchase)
VALUES (
    33333333-3333-3333-3333-333333333333,
    '2024-12-15 07:30:00+0000',
    uuid(), uuid(),
    5,
    'Powers my laptop and connects all peripherals flawlessly. No thermal throttling.',
    66, true
);

INSERT INTO product_reviews
    (product_id, review_date, review_id, user_id, rating, review_text, helpful_votes, verified_purchase)
VALUES (
    33333333-3333-3333-3333-333333333333,
    '2024-11-01 21:00:00+0000',
    uuid(), uuid(),
    3,
    'HDMI port only does 4K@30Hz. Fine for most things but gamers beware.',
    22, false
);

-- ── TTL demo: auto-expire after 60 seconds (for demo only) ───
INSERT INTO temp_reviews (product_id, review_id, review_text)
VALUES (
    11111111-1111-1111-1111-111111111111,
    uuid(),
    'This review will disappear after 60 seconds (TTL demo).'
) USING TTL 60;

-- ── Update counter ───────────────────────────────────────────
UPDATE product_review_counts
   SET review_count = review_count + 5
 WHERE product_id = 11111111-1111-1111-1111-111111111111;

UPDATE product_review_counts
   SET review_count = review_count + 3
 WHERE product_id = 22222222-2222-2222-2222-222222222222;

UPDATE product_review_counts
   SET review_count = review_count + 2
 WHERE product_id = 33333333-3333-3333-3333-333333333333;

-- ── Quick verification ───────────────────────────────────────
SELECT COUNT(*) FROM product_reviews;
