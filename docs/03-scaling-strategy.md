# Scaling Strategy

## 1. How scaling works

| Setting | Value | Why |
|---|---|---|
| Minimum instances | 2 while the stack is "up" (0 when stopped to save cost) | At least two instances, no cold start for normal use, survives losing one instance |
| Maximum instances | 30 | Cost and database-connection guard |
| Concurrency | 10 requests per instance | Earlier scale-out: Cloud Run adds instances when in-flight requests approach about 60% of this, or CPU is high |
| CPU / memory | 2 vCPU, 2 GiB per instance | CPU is the limit; larger instances mean fewer database connections |
| CPU allocation | Request-based (idle throttling), startup CPU boost on | Billing only while serving; faster Spring Boot start (about 6 s with AppCDS) |
| Probes | Startup and liveness on `/actuator/health/readiness` and `/liveness` | Traffic only reaches ready instances; unhealthy instances are restarted |
| Request timeout | 60 s | Bounded failure time |

The service is **stateless** (JWT, no session), so instances are interchangeable.

## 2. Capacity model

**Measured with the current configuration** (min 2, max 30, concurrency 10, 2 vCPU / 2 GiB, `db-custom-2-7680`): a sample test at 1,000 req/s held for 2 minutes (ramped from 500 over the first minute) ran on 19 instances throughout, about 53 requests per second per instance (1,000 / 19), with Cloud SQL CPU about 5% and client P95 392 ms. See `04-test-report.md`.

The figures below come from the earlier 1 vCPU configuration.

Measured on this service (see `04-test-report.md`): about **60 to 120 requests per second per 1-vCPU instance at roughly 60% CPU**. The planning figure used below is **100 req/s per instance**. This is a derived estimate from two runs, measured with light read queries against an empty catalogue, so it is an upper-bound style figure.

Assumption for the brief: 10,000 concurrent users, each sending one request every 2 seconds, gives **5,000 requests per second**.

| Quantity | Calculation | Result |
|---|---|---|
| Required request rate | 10,000 ÷ 2 s | 5,000 req/s |
| Instances needed at 60% CPU | 5,000 ÷ 100 | about 50 |
| Concurrent requests in flight (Little's law) | 5,000 req/s × about 0.03 s server time | about 150 |
| Instances needed by concurrency alone | 150 ÷ 48 (60% of 80) | about 4 |

**Insight:** for this application, **CPU, not concurrency, is the binding constraint**. Requests are fast, so few are in flight at once, but each consumes CPU. Scaling is therefore driven by CPU utilisation.

## 3. The database is part of the capacity plan

Each instance keeps a connection pool (default 10). At 50 to 60 instances that is 500 to 600 connections. The current database is `db-custom-2-7680` (2 vCPU, 7.5 GB), running; at 1,000 req/s its CPU was about 5%. The load-ready profile uses `db-custom-4-15360` (4 vCPU, 15 GB), and the pool size per instance should be reduced (for example to 5) at high instance counts. The connection limit of the chosen tier must be confirmed before using it for real load; this has not been verified.

## 4. What the load tests showed about scaling behaviour

- At moderate load (about 120 req/s peak) two instances were enough at about 30% CPU, which is expected behaviour: no scale-out is needed, and the instance count staying at 2 is correct.
- At a fast ramp to 400 simulated users, the instance count grew from 2 to about 9 (the cap was 10), CPU reached about 65% and latency rose to seconds while the new instances were starting. The cause is **scale-out lag** (a Spring Boot instance takes tens of seconds to become ready), not slow request handling, plus the instance cap being nearly reached.

## 5. Tuning levers (in order of effect)

| Lever | Effect | Status |
|---|---|---|
| Raise the minimum instance count shortly before expected load (for example 30 or more) | Capacity is already running when the spike arrives; removes the scale-out lag | **Hypothesis, not yet tested** |
| Raise the maximum (for example 60) | Removes the cap as a limit | Defined in `infra/terraform/profiles/load-ready.tfvars` |
| Upgrade the database tier, reduce pool size | Keeps the database from becoming the bottleneck | Defined in the load-ready profile; not applied (cost) |
| Lower concurrency | Scales out earlier on request count | Applied (concurrency 10); 19 instances at 1,000 req/s |
| 2 vCPU instances | Fewer, larger instances | Applied (2 vCPU / 2 GiB) |
| Cloud Run CPU quota increase for `us-central1` | Required for around 60 instances in a shared project | Status unknown |

Apply the profile on demand with:
`terraform apply -var-file=profiles/load-ready.tfvars`, then set the minimum with `gcloud run services update trebol-poc-app --min-instances <n>`. Terraform deliberately ignores the minimum so it does not fight `scripts/poc.ps1`.

## 6. Zero-downtime rollouts

New code ships as a new Cloud Run revision that first receives no traffic, is smoke-tested on its own tagged URL, then receives 10% of traffic and a bake check, and only then takes 100%. If any step fails, traffic goes back to the previous revision, which stayed warm the whole time. Because instances are stateless and the readiness probe gates traffic, no request is routed to an instance that is not ready. The success path was proven by deploy run #1 (revision `trebol-poc-app-g8854fbb-1`, 0 of 60 bake requests failed). The rollback path has not yet been exercised.

Known limitation: the bake check is synthetic (60 health requests to the canary), not real user traffic. After a rollback, traffic stays pinned to the older revision until the next successful deploy; changing the minimum instance count with `poc.ps1` in that state would create a revision that receives no traffic.
