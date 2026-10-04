-- ============================================================
-- 04: Dynamic Tables -- declarative, auto-refreshing transformations
-- ============================================================
-- Where Streams+Tasks give full control (needed above because we fire a
-- notification as a side effect), Dynamic Tables are the simpler choice
-- when all you need is "table B = transformed table A, kept fresh" with
-- no custom procedural logic or side effects required.

CREATE OR REPLACE DYNAMIC TABLE STAGING.STG_PRODUCTS_LIVE
    TARGET_LAG = '10 minutes'
    WAREHOUSE = COMPUTE_WH
AS
    SELECT
        product_id,
        product_name,
        category,
        CURRENT_TIMESTAMP() AS dbt_loaded_at
    FROM RAW.PRODUCTS
    WHERE product_id IS NOT NULL;

-- Downstream dynamic table built on top of another dynamic table --
-- Snowflake manages the refresh order and dependency graph automatically.
CREATE OR REPLACE DYNAMIC TABLE MARTS.PRODUCT_SUMMARY
    TARGET_LAG = '30 minutes'
    WAREHOUSE = COMPUTE_WH
AS
    SELECT
        category,
        COUNT(*) AS product_count
    FROM STAGING.STG_PRODUCTS_LIVE
    GROUP BY category;
