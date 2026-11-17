# Multi-Region Note (documented only, not implemented)

Multi-region was a bonus item. It was deliberately **not built**, to stay within the cost limit in a shared project. This note describes how the current design would extend.

## Target design

| Layer | Approach |
|---|---|
| Entry | A global external HTTPS load balancer with serverless network endpoint groups, one per region, routing users to the nearest healthy region |
| Compute | The same Terraform module instantiated per region (for example `us-central1` and `us-east1`), each with its own Cloud Run service, minimum instances and VPC |
| Database | Cloud SQL primary in one region with a cross-region read replica; promotion for disaster recovery. Writes stay in the primary region |
| Secrets and images | Secret Manager and Artifact Registry replicate or are pulled per region |
| Observability | One dashboard and alert set across regions, using a region label |

## What the current design already provides

The service is stateless (JWT), configuration is by environment variables, and everything is Terraform, so adding a region means instantiating the same code with different inputs. The deploy workflow would deploy the same image to each region, one region at a time, using the same canary and rollback steps.

## What would need decisions

- Whether writes can tolerate cross-region latency to a single primary, or the application needs a different data strategy.
- The database failover procedure and its recovery-time target.
- Cost: roughly double the compute, plus a replica and a load balancer. Not acceptable inside the USD 50 per month limit.
- A public entry point, which the organisation's current policy blocks (see `02-deployment-guide.md`).
