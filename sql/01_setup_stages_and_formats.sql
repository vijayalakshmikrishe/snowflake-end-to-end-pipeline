-- ============================================================
-- 01: Database, schema, file format, and external stage setup
-- ============================================================

CREATE DATABASE IF NOT EXISTS ANALYTICS_PLATFORM;
USE DATABASE ANALYTICS_PLATFORM;

CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS STAGING;
CREATE SCHEMA IF NOT EXISTS MARTS;
CREATE SCHEMA IF NOT EXISTS CONTROL;   -- pipeline observability / control tables

-- File format for incoming CSV extracts
CREATE OR REPLACE FILE FORMAT RAW.CSV_STANDARD
    TYPE = CSV
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('NULL', 'null', '');

-- External stage pointing at the S3 landing location.
-- STORAGE_INTEGRATION should be created separately (requires an IAM role
-- trust relationship on the AWS side) -- referenced here, not redefined,
-- since integration setup is account/IAM-specific.
CREATE OR REPLACE STAGE RAW.S3_LANDING_STAGE
    URL = 's3://your-landing-bucket/pipeline-extracts/'
    STORAGE_INTEGRATION = s3_integration
    FILE_FORMAT = RAW.CSV_STANDARD;

-- Control table: tracks every pipeline run for observability.
-- This is what the Streamlit dashboard and Python validators write to
-- and read from.
CREATE TABLE IF NOT EXISTS CONTROL.PIPELINE_RUN_LOG (
    run_id            NUMBER AUTOINCREMENT,
    pipeline_name     VARCHAR,
    run_start_ts      TIMESTAMP_NTZ,
    run_end_ts        TIMESTAMP_NTZ,
    status            VARCHAR,          -- 'success' | 'fail'
    rows_loaded       NUMBER,
    error_message     VARCHAR
);
