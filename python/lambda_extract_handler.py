"""
Example AWS Lambda handler: pulls an extract from an external source
system's API and lands it in S3, where an S3 event notification then
triggers Snowpipe auto-ingestion (see sql/02_snowpipe_setup.sql).

This mirrors a real two-Lambda integration pattern used for a source
system with no native S3 connectivity: this first Lambda calls the
source API using a workspace/model identifier and writes the extract to
S3; landing that file is itself the event that triggers the next stage
(Snowpipe), so no polling is required anywhere in the chain.

In production this would be deployed as an actual AWS Lambda function,
triggered by EventBridge on a schedule or by an upstream API webhook.
"""

import json
import logging
from datetime import datetime
from typing import Any

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

S3_BUCKET = "your-landing-bucket"
S3_PREFIX = "pipeline-extracts/customers"


def fetch_extract_from_source(workspace_id: str, model_id: str) -> dict[str, Any]:
    """
    Calls the external source system's API to pull an extract for the
    given workspace/model. Replace with the real API client/SDK call.
    """
    logger.info(f"Fetching extract for workspace={workspace_id}, model={model_id}")
    # Placeholder for the real API call, e.g.:
    # response = source_api_client.get_export(workspace_id, model_id)
    # return response.json()
    return {"workspace_id": workspace_id, "model_id": model_id, "rows": []}


def write_to_s3(data: dict[str, Any], bucket: str, key: str) -> None:
    s3 = boto3.client("s3")
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(data),
        ContentType="application/json",
    )
    logger.info(f"Wrote extract to s3://{bucket}/{key}")


def handler(event: dict, context: Any) -> dict:
    """
    Lambda entry point. Expects event to contain workspace_id and
    model_id -- e.g. passed by an EventBridge scheduled rule, or by an
    upstream webhook from the source system.
    """
    workspace_id = event["workspace_id"]
    model_id = event["model_id"]

    extract = fetch_extract_from_source(workspace_id, model_id)

    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    key = f"{S3_PREFIX}/extract_{workspace_id}_{timestamp}.json"
    write_to_s3(extract, S3_BUCKET, key)

    # Landing this file in S3 is itself the trigger for the next stage:
    # an S3 event notification fires Snowpipe's auto-ingest (configured
    # in sql/02_snowpipe_setup.sql), so no second Lambda call is needed
    # here to "kick off" ingestion -- it happens automatically.

    return {
        "statusCode": 200,
        "body": json.dumps({"status": "success", "s3_key": key}),
    }


if __name__ == "__main__":
    # Local test invocation
    test_event = {"workspace_id": "WS123", "model_id": "MODEL456"}
    print(handler(test_event, None))
