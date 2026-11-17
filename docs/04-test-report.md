# Load Test Report and Tuning

## 1. Scope and honesty statement

The brief asks for a test at 10,000 concurrent users with P95 below 500 ms and errors below 1%. **That test was not run from our side.** The agreed approach was to (a) measure the real behaviour of one instance with small tests, (b) size and document a configuration that should meet the target, and (c) let the evaluators run the full test. Everything labelled *projected* below is arithmetic from measured values, not a measured result.

## 2. Method

- Tool: k6 (official `grafana/k6` image run through Docker, since installing k6 on the laptop needs admin rights).
- Scripts: `loadtest/ramp.js` (up to 50 users) and `loadtest/ramp-high.js` (up to 400 users).
- Targets: `GET /data/products`, `GET /data/product_categories`, `GET /public/about`, chosen at random with a 0.1 s pause. These are read queries that go through the connection pool to Cloud SQL. The products table is empty, so queries are lighter than with real catalogue data.
- Access: private service, Google identity token in `X-Serverless-Authorization`.
- Pass criteria (same as the brief): P95 under 500 ms, error rate under 1%.
- **Client location:** the load generator ran from a laptop in India (UTC+5:30) against `us-central1`. The network round trip is about 280 to 300 ms, which is the minimum request time seen in every run (min 278 to 296 ms). Client-side latency is therefore inflated by network distance. The server-side latency in Cloud Run Metrics is the figure that reflects the application.

## 3. Results

| Run | Load | Requests | Avg rate | Errors | Client P95 | Instances | CPU (P95) | Thresholds |
|---|---|---|---|---|---|---|---|---|
| Sanity | 1 user, 10 s | 24 | 2.4 req/s | 0% | 330 ms | 2 | n/a | pass |
| Ramp 1 | up to 50 users, 3.5 min | 15,438 | 73 req/s (peak about 120) | 0% | 390 ms (avg 316 ms, max 1.6 s) | stayed at 2 | about 30% | pass |
| Ramp 2 | up to 400 users, 4.5 min | 83,487 | 309 req/s (peak about 500) | 0% | **2.16 s** (P90 1.88 s, median 361 ms, max 31.4 s) | 2 to about 9 | about 65% | **P95 failed** |

Server-side (Cloud Run Metrics): in Ramp 1, latency was in the tens of milliseconds once warm. In Ramp 2, server-side P50 / P95 / P99 rose to about 1.2 s / 2.3 s / 3 s during the ramp. Memory stayed near 50% in all runs.

**No request failed in any run** (83,487 of 83,487 returned HTTP 200). The failure in Ramp 2 is latency only.

### Sample test at 1,000 req/s (current configuration)

Configuration: min 2, max 30, concurrency 10, 2 vCPU / 2 GiB with idle throttling, database `db-custom-2-7680`. Load: 1,000 requests per second held for 2 minutes, ramped from 500 over the first minute.

| Metric | Result |
|---|---|
| Target rate | 1,000 req/s |
| Client latency, median | 310 ms |
| Client latency, P90 | 350 ms |
| Client latency, P95 | 392 ms (target 500 ms: passed) |
| Client latency, P99 | 601 ms |
| Client latency, max | 5.9 s (one outlier) |
| Instances | 19 throughout |
| Cloud SQL CPU | about 5% |

The earlier runs above used the previous configuration (1 vCPU / 1 GiB, concurrency 80, max 10, `db-f1-micro`).

## 4. Analysis

1. **Ramp 1 passed, and instance count staying at 2 is correct.** At 73 to 120 req/s with fast responses, only a few requests are in flight at any moment, so there is no reason to add instances. The measured test was limited by the client (each user waits about 0.4 s per reply because of the distance), not by the service.
2. **Ramp 2 failed the P95 target because of scale-out lag.** The load went from zero to 400 users in two minutes. The autoscaler had to add about 7 instances; each Spring Boot instance needs tens of seconds to become ready. Meanwhile, the instances that existed were saturated and requests queued (worst wait 31 s). The instance count also approached the cap of 10. The application did not fail; it was under-provisioned for a sudden spike.
3. **Per-instance throughput (derived):** about 60 to 120 req/s per 1-vCPU instance at roughly 60% CPU. The planning figure used in `03-scaling-strategy.md` is 100 req/s.
4. **Limitations:** empty catalogue (light queries), network distance inflates client latency, only two moderate load runs, no measurement of Cloud SQL CPU or connections during the runs.

## 5. Tuning plan

| Change | Reason | Status |
|---|---|---|
| Pre-warm: raise the minimum instances before the load (for example 8 for a 400-user test, about 30 or more for the full target) | Removes the scale-out lag that caused the P95 miss | Hypothesis. A rerun with minimum 8 and maximum 20 was prepared but **not executed** |
| Raise the maximum instances to 60 | Cap was nearly reached | In `profiles/load-ready.tfvars` |
| Larger database tier (`db-custom-4-15360`), smaller pool per instance | Avoid a database bottleneck at 50+ instances | In the load-ready profile; not applied |
| Cloud Run CPU quota for about 60 instances | Needed for the above in a shared project | Status unknown |

## 6. Projection for 10,000 users (not measured)

Assumption: each user sends one request every 2 seconds, so 5,000 req/s. At about 100 req/s per instance, about 50 instances are needed near 60% CPU; with the maximum at 60 there is roughly 20% headroom. With the minimum raised in advance so that capacity is already running, the expectation is that server-side P95 would stay close to the low-latency behaviour seen in Ramp 1. This is an expectation based on two runs and has not been demonstrated.

## 7. What the evaluators should know

- Run their load from a location close to `us-central1`, or compare against the server-side latency metric.
- Raise the minimum instance count (or ask us to) shortly before the test.
- The service is private; they need invoker access and a Google identity token in `X-Serverless-Authorization`.

## 8. Optimisation round (P95 under load)

### What was changed
- **Image (`trebol-backend-monolith/Dockerfile`)**: only the layers on the classpath, application classes packaged as a jar, an AppCDS archive built with the runtime JVM, SerialGC, C1-only JIT, 512k thread stacks, `lombok` jar removed, BuildKit Maven cache mount, `COPY --link`. Local startup on 1 CPU / 1 GB: about 21 s before, about 6 s after (on an idle machine). Image size 463 MB to about 583 MB (the CDS archive).
- **Catalogue cache**: Caffeine, 30 s TTL, evicted on any write, for the product and category lists and `/public/about`. Other instances can serve a previous list for up to 30 s.
- **Database tier**: `db-f1-micro` to `db-custom-2-7680`. Applied with gcloud, not Terraform.
- **Cloud Run**: per-instance concurrency 80 to 10 (scale-out starts earlier), 2 vCPU / 2 GiB. Applied with gcloud, not Terraform.
- **`scripts/loadtest-mode.ps1`**: temporary scale-up for a test window with automatic restore of the saved settings. `loadtest/scale.js` (N users) and `loadtest/rate.js` (fixed req/s) were added.

### Findings (Cloud Run, load from a laptop in India, so client latency includes about 290 ms of network)

| Run | Settings | Client P95 | Server P95 | Notes |
|---|---|---|---|---|
| 400 users, original image, small DB | min 2, max 10, conc 80 | 2.16 s | about 2.3 s | scale-out lag |
| 400 users, new image, conc 30, small DB | min 8, max 20 | 2.65 s | 2.07 s | 23% of requests over 1 s |
| 400 users, conc 10, small DB | min 8, max 20 | 2.67 s | 1.10 s | 6.4% over 1 s |
| 400 users, min 14 + pre-created DB connections | min 14, max 20 | 2.91 s | 1.98 s | no improvement, change dropped |
| 400 users, new image, **bigger DB** | min 8, max 20, conc 10 | **390 ms** | 21 ms | 180,247 requests, 0 errors |
| 400 users, cache + layered image, bigger DB | min 8, max 20, conc 10 | **423 ms** | n/a | 175,128 requests, 0 errors |
| 1,000 users (1 req/s each), boosted | min 15, max 30 | 800 ms | 10 ms | 509 req/s |
| 1,000 users (1 req/s each), unboosted | min 2, max 30, conc 10, throttled | 626 ms | 10 ms (172 ms in minute 1) | 523 req/s, 0 errors |
| **1,000 req/s fixed rate, unboosted** | min 2, max 30, conc 10, throttled | **392 ms** | 10 ms | 179,985 requests, 1 failure, passes the 500 ms threshold |
| 5,000 users, boosted | min 40, max 60 | 11.6 s | 10 ms | **invalid**: the laptop generated only 795 req/s |

Root cause of the remaining tail: the `db-f1-micro` shared-core database. In the first two minutes of a 400-user run the server answered in 7 ms (P50) and 13 to 24 ms (P95); once load reached about 400 users every instance slowed at once while container CPU stayed low. With the bigger database the same test gave server P95 of 21 ms. Cloud SQL CPU stayed near 5% at 1,000 req/s.

### Limits of these results
- Traffic is read-only on an empty catalogue. Checkout, login and larger data will cost more per request.
- The 5,000-user run measured the load generator, not the service. It needs a client in `us-central1` (or several clients).
- Instance counts topped out around 19 to 20 even with higher minimums and maximums. A Cloud Run CPU quota in the shared project is suspected, not confirmed.
- The cache effect was not isolated on the small database (not tested).
- The bigger database costs about $0.14 per hour (about $100 per month if left on), against about $0.015 per hour for `db-f1-micro`. Prices are approximate list prices and should be checked.
