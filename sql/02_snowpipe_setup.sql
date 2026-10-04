-- ============================================================
-- 02: Snowpipe -- near-real-time auto-ingestion from S3
-- ============================================================
-- Snowpipe does NOT poll S3. It is event-driven: an S3 event
-- notification (via SQS) tells Snowflake a new file has landed, and
-- Snowpipe loads just that file using Snowflake-managed serverless
-- compute -- no warehouse required for the ingestion itself.

CREATE TABLE IF NOT EXISTS RAW.CUSTOMERS (
    customer_id        NUMBER,
    customer_name       VARCHAR,
    email               VARCHAR,
    region              VARCHAR,
    signup_date         DATE,
    last_modified_date  TIMESTAMP_NTZ
);

CREATE OR REPLACE PIPE RAW.CUSTOMERS_PIPE
    AUTO_INGEST = TRUE
AS
    COPY INTO RAW.CUSTOMERS
    FROM @RAW.S3_LANDING_STAGE/customers/
    FILE_FORMAT = (FORMAT_NAME = RAW.CSV_STANDARD);

-- After creating the pipe, SHOW PIPES retrieves the notification_channel
-- (an SQS ARN) that must be configured as the event destination on the
-- S3 bucket -- this is the piece done on the AWS side, not in Snowflake.
-- SHOW PIPES LIKE 'CUSTOMERS_PIPE';

-- ------------------------------------------------------------
-- Batch alternative: COPY INTO on a schedule, for predictable,
-- larger loads where serverless-per-file billing isn't cost-effective.
-- Uses a warehouse you size and control, instead of serverless compute.
-- ------------------------------------------------------------
CREATE OR REPLACE TASK RAW.LOAD_ORDERS_BATCH
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 0 2 * * * UTC'   -- nightly at 2am
AS
    COPY INTO RAW.ORDERS
    FROM @RAW.S3_LANDING_STAGE/orders/
    FILE_FORMAT = (FORMAT_NAME = RAW.CSV_STANDARD);

ALTER TASK RAW.LOAD_ORDERS_BATCH RESUME;
