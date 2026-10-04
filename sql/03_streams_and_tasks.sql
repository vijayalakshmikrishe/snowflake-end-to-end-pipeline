-- ============================================================
-- 03: Streams + Tasks -- event-driven incremental processing
-- ============================================================
-- Pattern: a Task runs on a schedule and checks whether the Stream on a
-- table has new data. If so, it calls a stored procedure that consumes
-- the Stream (processes the changed rows) and, as part of that same
-- procedure, notifies downstream systems -- so nothing downstream runs
-- unless there's actually something new to process.

-- Stream watches RAW.CUSTOMERS for inserts/updates/deletes since it was
-- last read.
CREATE OR REPLACE STREAM RAW.CUSTOMERS_STREAM ON TABLE RAW.CUSTOMERS;

-- Stored procedure: consumes the stream, loads to staging, logs the run.
CREATE OR REPLACE PROCEDURE STAGING.SP_PROCESS_CUSTOMER_CHANGES()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    row_count INTEGER;
    start_ts TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP();
BEGIN
    -- Reading from the stream is what marks these changes as consumed.
    CREATE OR REPLACE TEMPORARY TABLE stg_changes AS
        SELECT * FROM RAW.CUSTOMERS_STREAM;

    SELECT COUNT(*) INTO :row_count FROM stg_changes;

    MERGE INTO STAGING.STG_CUSTOMERS AS tgt
    USING stg_changes AS src
    ON tgt.customer_id = src.customer_id
    WHEN MATCHED AND src.METADATA$ACTION = 'INSERT' AND src.METADATA$ISUPDATE THEN
        UPDATE SET
            tgt.customer_name = src.customer_name,
            tgt.email = LOWER(TRIM(src.email)),
            tgt.region = src.region
    WHEN NOT MATCHED AND src.METADATA$ACTION = 'INSERT' THEN
        INSERT (customer_id, customer_name, email, region, signup_date)
        VALUES (src.customer_id, src.customer_name, LOWER(TRIM(src.email)), src.region, src.signup_date);

    -- Log the run to the control table for dashboard visibility.
    INSERT INTO CONTROL.PIPELINE_RUN_LOG
        (pipeline_name, run_start_ts, run_end_ts, status, rows_loaded)
    VALUES
        ('process_customer_changes', :start_ts, CURRENT_TIMESTAMP(), 'success', :row_count);

    -- In production: this is where an SNS notification / external
    -- function call would fire, signalling downstream systems that new
    -- data is ready -- only after the load has succeeded.
    -- CALL UTIL.PUBLISH_SNS_NOTIFICATION('customer_data_updated', :row_count);

    RETURN 'Processed ' || row_count || ' changed customer row(s)';
END;
$$;

-- Task: wakes up every 5 minutes, but only actually runs the procedure
-- if the stream has data -- no wasted compute on empty checks.
CREATE OR REPLACE TASK STAGING.TASK_PROCESS_CUSTOMER_CHANGES
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '5 MINUTE'
WHEN
    SYSTEM$STREAM_HAS_DATA('RAW.CUSTOMERS_STREAM')
AS
    CALL STAGING.SP_PROCESS_CUSTOMER_CHANGES();

ALTER TASK STAGING.TASK_PROCESS_CUSTOMER_CHANGES RESUME;
