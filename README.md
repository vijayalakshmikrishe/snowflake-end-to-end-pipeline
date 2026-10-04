# End-to-End Snowflake Data Engineering Pipeline

Infrastructure-as-SQL for a production-style Snowflake ingestion and
orchestration layer: event-driven ingestion, change-data-capture
processing, declarative transformations, clustering, cost control, and
compliance-aware access -- the platform layer that the other repos in
this portfolio build on top of.

## Architecture

```
External source (API)
        │
        ▼
  AWS Lambda ──────────▶ S3 (landing)
                             │
                   S3 event notification
                             │
                             ▼
                        Snowpipe (auto-ingest, serverless)
                             │
                             ▼
                        RAW layer (tables)
                             │
              ┌──────────────┴──────────────┐
              ▼                              ▼
     Stream (change capture)         Dynamic Table
              │                     (declarative refresh,
              ▼                      no side effects needed)
     Task (checks stream,
     calls stored procedure)
              │
              ▼
     STAGING layer (MERGE / upsert)
              │
              ▼
     MARTS layer (fact/dim tables --
     see subscription-analytics-dbt-snowflake
     for the dimensional model itself)
              │
              ▼
     CONTROL.PIPELINE_RUN_LOG
     (feeds streamlit-data-quality-dashboard)
```

## What's in here, and why

| File | Demonstrates |
|---|---|
| `01_setup_stages_and_formats.sql` | Database/schema design, external stages, a control table for pipeline observability |
| `02_snowpipe_setup.sql` | Event-driven ingestion via Snowpipe (serverless, auto-ingest) **and** scheduled batch loading via `COPY INTO` + Task, with the reasoning for choosing one over the other |
| `03_streams_and_tasks.sql` | Change-data-capture: a Task checks a Stream and only runs when there's genuinely new data, consumes it via `MERGE`, and logs the run -- the same pattern used for a real truncate-and-reload source integration |
| `04_dynamic_tables.sql` | Declarative, auto-refreshing transformations for cases that don't need custom procedural logic or side effects |
| `05_clustering_and_optimization.sql` | Clustering keys for pruning on large fact tables, warehouse sizing/auto-suspend for cost control, multi-cluster warehouses for concurrency, and secure views for masking PII |
| `python/lambda_extract_handler.py` | The AWS side of the ingestion chain: a Lambda pulling an extract from a source system with no native S3 connectivity, landing it in S3 to trigger the Snowpipe stage |

## Key design decisions (and why)

- **Snowpipe vs. scheduled `COPY INTO`**: Snowpipe is event-driven and
  uses serverless compute, ideal for frequent small files. For large,
  predictable nightly batches, a scheduled `COPY INTO` on a right-sized
  warehouse is often cheaper and simpler -- this is a cost/predictability
  trade-off, not a capability difference, and both patterns are included.
- **Streams+Tasks vs. Dynamic Tables**: Streams+Tasks are used where a
  pipeline needs custom procedural logic or a side effect (here,
  conditionally triggering downstream notification only on success).
  Dynamic Tables are used where the need is simpler: "keep this
  transformed table fresh," with no side effects required.
- **Clustering is applied deliberately, not by default**: only on a
  large fact table where the filtered/joined column doesn't naturally
  correlate with load order -- clustering has a real maintenance cost
  and isn't a blanket best practice.
- **Secure views for PII**: compliance-sensitive columns are exposed
  through a secure view rather than direct table grants, since secure
  views also prevent the query optimizer from leaking data through
  pushed-down predicates.

## Running this

These scripts assume a Snowflake account with `ACCOUNTADMIN` or
equivalent privileges for the initial setup (database/warehouse/stage
creation), and an S3 bucket with a configured storage integration for
the Snowpipe and Lambda pieces. Run the SQL files in numeric order:

```
snowsql -f sql/01_setup_stages_and_formats.sql
snowsql -f sql/02_snowpipe_setup.sql
snowsql -f sql/03_streams_and_tasks.sql
snowsql -f sql/04_dynamic_tables.sql
snowsql -f sql/05_clustering_and_optimization.sql
```

The Lambda handler in `python/` is illustrative of the integration
pattern; deploying it for real requires packaging it with `boto3` and
the source system's API client, and configuring the actual S3 event
notification → SQS → Snowpipe wiring on the AWS side.

## How this fits the rest of the portfolio

- **`python-etl-metadata-framework`** generates the stored procedures
  this pipeline's Tasks call.
- **`subscription-analytics-dbt-snowflake`** owns the dimensional
  modeling of the MARTS layer this pipeline populates.
- **`streamlit-data-quality-dashboard`** reads `CONTROL.PIPELINE_RUN_LOG`,
  populated here, to surface pipeline health.
