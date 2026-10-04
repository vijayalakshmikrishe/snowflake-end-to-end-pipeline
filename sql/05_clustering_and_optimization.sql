-- ============================================================
-- 05: Clustering and cost/performance optimization
-- ============================================================
-- As fact tables grow over time, rows land in micro-partitions in load
-- order. If queries frequently filter/join on a column that doesn't
-- naturally correlate with load order (e.g. customer_id on a large fact
-- table), pruning effectiveness degrades -- a clustering key tells
-- Snowflake to physically reorganize data to restore it.

ALTER TABLE MARTS.FACT_SUBSCRIPTION_ACTIVITY
    CLUSTER BY (customer_key, date_key);

-- Check clustering health/quality on a clustered table.
SELECT SYSTEM$CLUSTERING_INFORMATION('MARTS.FACT_SUBSCRIPTION_ACTIVITY', '(customer_key, date_key)');

-- ------------------------------------------------------------
-- Warehouse sizing and cost control
-- ------------------------------------------------------------

-- A right-sized warehouse per workload, with auto-suspend so compute
-- isn't billed while idle, and auto-resume so it's available on demand.
CREATE WAREHOUSE IF NOT EXISTS ETL_WH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 60          -- seconds of inactivity before suspending
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

-- Multi-cluster warehouse for concurrency (many simultaneous users/
-- queries), scaling OUT rather than UP -- a different lever than
-- warehouse size, which scales an individual query's compute.
CREATE WAREHOUSE IF NOT EXISTS BI_WH
    WAREHOUSE_SIZE = 'SMALL'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 3
    SCALING_POLICY = 'STANDARD'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;

-- ------------------------------------------------------------
-- Secure views for compliance-sensitive columns
-- ------------------------------------------------------------
-- A secure view hides its query definition and blocks the optimizer
-- from pushing predicates in a way that could leak protected data
-- through query plans -- used here to mask PII for broader access.
CREATE OR REPLACE SECURE VIEW MARTS.CUSTOMER_MASKED AS
    SELECT
        customer_key,
        region,
        segment,
        -- Mask email for roles without direct PII access
        CONCAT(LEFT(email, 2), '***@***') AS email_masked
    FROM MARTS.DIM_CUSTOMER;

GRANT SELECT ON VIEW MARTS.CUSTOMER_MASKED TO ROLE ANALYST;
