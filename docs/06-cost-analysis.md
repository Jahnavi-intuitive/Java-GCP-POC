# Cost Analysis

All figures are planning estimates, not invoices. Check the Billing console for actuals. Prices change; recheck with the Google Cloud pricing calculator before relying on them.

## 1. Constraint

The company limit for this POC is under **USD 50 per month**, in a project shared with other users. The stack is therefore kept running only about 4 to 5 hours on weekdays.

## 2. What costs money

| Component | Cost driver | How it is kept low |
|---|---|---|
| Cloud Run | vCPU-seconds and memory while serving, plus the minimum instances while they are kept warm | Request-based billing; minimum instances 0 when stopped, 2 only while the stack is up |
| Cloud SQL (`db-custom-2-7680`, 10 GB SSD) | Instance hours plus storage and backups | Instance stopped (`activation_policy NEVER`) outside working hours; storage and backups still accrue; autoresize limit 20 GB |
| Artifact Registry | Storage | Cleanup policies keep the 10 most recent images and delete older than 30 days |
| Secret Manager, Cloud Logging, Cloud Monitoring | Small volumes | Free tiers expected to cover this usage |
| Networking | VPC, private services access | No cost for the VPC itself; no NAT or load balancer is used |
| GitHub Actions | Minutes | Free allowance; the PR build runs about 5 minutes |

## 3. Estimated monthly cost

These are estimates from Google's published list prices and the live configuration, not billing data; check the Billing console for actuals. Assumed usage: stack up 5 hours a day, 22 weekdays = 110 hours a month.

| Rate used (us-central1) | Price |
|---|---|
| Cloud Run request-based CPU, active / idle | USD 0.000024 / 0.0000025 per vCPU-second |
| Cloud Run request-based memory | USD 0.0000025 per GiB-second |
| Cloud Run instance-based (CPU always on) | USD 0.000018 per vCPU-second, 0.000002 per GiB-second |
| Cloud Run requests | USD 0.40 per million (2 million free per month) |
| Cloud SQL MySQL Enterprise | USD 0.0413 per vCPU-hour, 0.007 per GB-hour |
| Cloud SQL SSD storage | about USD 0.17 per GB-month |

| Item | Calculation | Per month |
|---|---|---|
| Cloud SQL `db-custom-2-7680` compute | (2 x 0.0413 + 7.5 x 0.007) = USD 0.135 per hour x 110 h | about USD 14.9 |
| Cloud SQL storage (billed even when stopped) | 10 GB x 0.17 | about USD 1.7 |
| Cloud Run, 2 idle instances (2 vCPU / 2 GiB) | 2 x (2 x 0.0000025 + 2 x 0.0000025) x 3,600 x 110 | about USD 7.9 |
| Total, baseline | | about USD 25 |
| Sample test at 1,000 req/s (19 instances, about 3 minutes active) | 19 x 180 s x (2 x 0.000024 + 2 x 0.0000025) | about USD 0.2 |

| Boosted capacity (CPU always on, 2 vCPU / 2 GiB) | Cost per hour |
|---|---|
| 1 instance | about USD 0.14 |
| 19 instances | about USD 2.7 |
| 30 instances | about USD 4.3 |

Estimated total: about USD 25 to 30 per month including load-test windows, against the USD 50 limit. Cloud SQL is the largest item; stopping it with `poc.ps1 down` removes its compute charge. Free tiers (Cloud Run CPU and memory, 2 million requests) reduce the figure slightly. Backups, Artifact Registry storage, Secret Manager and logging are small and not included.

## 4. Load-ready profile (not applied)

The projected profile (maximum 60 instances, `db-custom-4-15360`) costs far more than the baseline while running: dozens of instances at 1 vCPU each plus a 4 vCPU database. It should only be applied for a short evaluation window and then reverted. Price it in the calculator before applying; no figure is stated here because it was not calculated.

## 5. Controls in place

- `scripts/poc.ps1 down` stops the database and sets Cloud Run to zero instances.
- Resources are labelled (`owner=jahnavi`, `poc=trebol`) so the budget can be filtered to this POC.
- Cloud SQL storage auto-increase is capped at 20 GB.

## 6. Open items

- **A billing budget has not been created.** It needs billing permission from an administrator. Requested alert thresholds: USD 25, 40 and 50, filtered by label `poc=trebol`. Budgets only send notifications; they do not stop spending.
- MySQL 8.0 enters extended support (an extra per-hour charge) from 1 January 2027. Upgrading to MySQL 8.4 avoids it; this is a planned follow-up.

## 7. Further savings if needed

Stop the database sooner each day; lower the minimum instances to 1 for non-demo use; remove old image tags manually.
