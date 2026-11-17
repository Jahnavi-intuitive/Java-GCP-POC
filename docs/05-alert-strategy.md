# Alerting and Observability Strategy

## 1. Logging

Cloud Run writes request logs and application output to **Cloud Logging**, which is the central log store. No agent is needed. A log-based metric (`trebol_poc_app_errors`) counts log entries with severity ERROR or higher for the service, so application errors become a chartable, alertable number.

## 2. Dashboard

Terraform creates the dashboard **"trebol-poc: service overview"** (Monitoring, Dashboards) with eight charts:

| Chart | Metric | Answers |
|---|---|---|
| Requests per second by status class | `request_count` by `response_code_class` | How much traffic, and how much of it fails |
| Error rate: 5xx per second | `request_count`, 5xx | Is the service failing |
| Latency P95 and P50 (ms) | `request_latencies` | The brief's latency criterion |
| Health: container instances (active / idle) | `container/instance_count` | Are instances running, is it scaling |
| CPU utilisation P95 | `container/cpu/utilizations` | The scaling signal |
| Memory utilisation P95 | `container/memory/utilizations` | Memory pressure |
| Application ERROR log entries per second | log-based metric | Errors inside the app |

## 3. Alert policies

All alerts notify an email channel (`alert_email` variable, default the owner's address) and auto-close after 30 minutes without recurrence.

| Alert | Condition | Duration | Why |
|---|---|---|---|
| 5xx error rate above 1% | 5xx requests divided by all requests above 0.01 | 5 min | Direct mapping of the brief's error criterion |
| P95 latency above 500 ms | P95 request latency above 500 ms | 5 min | Direct mapping of the brief's latency criterion |
| CPU above 80% | P95 container CPU above 0.8 | 5 min | Early sign that scale-out lag is coming |
| TEST ALERT (4xx burst) | 4xx rate above 0.05 req/s | immediate | Deliberately easy to trigger, to prove the alert path |

Why these thresholds: five-minute durations avoid paging on short blips such as a single cold start; the error and latency numbers are the brief's own acceptance limits. With no traffic, the ratio and latency alerts have no data and stay quiet, so the alerts need no switching on and off when the stack is stopped.

## 4. Firing the test alert

With the stack up, send about 20 requests to a URL that does not exist (the app answers 404, a 4xx):

```powershell
$TOKEN = gcloud.cmd auth print-identity-token
1..20 | ForEach-Object { curl.exe -s -o NUL -H "X-Serverless-Authorization: Bearer $TOKEN" "<service url>/does-not-exist" }
```

Within about 2 to 5 minutes an email arrives and an incident appears under Monitoring, Alerting. **Status: not yet fired.** Capture the email and the incident as demo evidence, then stop the stack.

## 5. Runbook

| Alert | First checks | Typical action |
|---|---|---|
| 5xx error rate | Logs (severity ERROR) for the failing revision; is the database up; did a deploy just happen | If a recent revision is the cause, roll traffic back to the previous one; if the database is stopped, start it |
| P95 latency | Instance count and CPU on the dashboard | If CPU is high and instances are few, raise the minimum instances; if the database is slow, check Cloud SQL |
| CPU above 80% | Instance count against the maximum | Raise the maximum; consider more vCPU |
| Test alert | Expected during the demo | Close the incident |

## 6. Gaps

No uptime check is configured because the service is private (checks would need an authenticated check). The dashboard has no database panels; adding Cloud SQL CPU and connections is the recommended next step, since the database is the likely limit at high instance counts.
