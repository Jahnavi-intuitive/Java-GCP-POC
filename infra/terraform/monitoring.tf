locals {
  svc = google_cloud_run_v2_service.app.name
  base_filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.svc}\""
  rc_filter   = "${local.base_filter} AND metric.type=\"run.googleapis.com/request_count\""
}

# 1. Where alerts go
resource "google_monitoring_notification_channel" "email" {
  display_name = "trebol-poc alerts (email)"
  type         = "email"
  labels       = { email_address = var.alert_email }
}

# 2. Log-based metric: application errors seen in the central logs
resource "google_logging_metric" "app_errors" {
  name   = "trebol_poc_app_errors"
  filter = "${local.base_filter} AND severity>=ERROR"
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# 3. Alerts
resource "google_monitoring_alert_policy" "error_rate" {
  display_name = "trebol-poc: 5xx error rate above 1%"
  combiner     = "OR"
  conditions {
    display_name = "5xx / all requests > 1% for 5 min"
    condition_threshold {
      filter             = "${local.rc_filter} AND metric.labels.response_code_class=\"5xx\""
      denominator_filter = local.rc_filter
      comparison         = "COMPARISON_GT"
      threshold_value    = 0.01
      duration           = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
      denominator_aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
      trigger { count = 1 }
    }
  }
  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy { auto_close = "1800s" }
}

resource "google_monitoring_alert_policy" "latency_p95" {
  display_name = "trebol-poc: P95 latency above 500 ms"
  combiner     = "OR"
  conditions {
    display_name = "P95 latency > 500 ms for 5 min"
    condition_threshold {
      filter          = "${local.base_filter} AND metric.type=\"run.googleapis.com/request_latencies\""
      comparison      = "COMPARISON_GT"
      threshold_value = 500
      duration        = "300s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_PERCENTILE_95"
        cross_series_reducer = "REDUCE_MAX"
      }
      trigger { count = 1 }
    }
  }
  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy { auto_close = "1800s" }
}

resource "google_monitoring_alert_policy" "cpu_high" {
  display_name = "trebol-poc: CPU above 80%"
  combiner     = "OR"
  conditions {
    display_name = "P95 container CPU > 80% for 5 min"
    condition_threshold {
      filter          = "${local.base_filter} AND metric.type=\"run.googleapis.com/container/cpu/utilizations\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_PERCENTILE_95"
        cross_series_reducer = "REDUCE_MAX"
      }
      trigger { count = 1 }
    }
  }
  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy { auto_close = "1800s" }
}

# Test alert: fires on demand by sending a few requests to a non-existent URL
resource "google_monitoring_alert_policy" "test_alert" {
  display_name = "trebol-poc: TEST ALERT (4xx burst, fire on demand)"
  combiner     = "OR"
  conditions {
    display_name = "4xx rate > 0.05 req/s"
    condition_threshold {
      filter          = "${local.rc_filter} AND metric.labels.response_code_class=\"4xx\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.05
      duration        = "0s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
      trigger { count = 1 }
    }
  }
  notification_channels = [google_monitoring_notification_channel.email.id]
  alert_strategy { auto_close = "1800s" }
}

# 4. Dashboard
locals {
  m = "${local.base_filter} AND metric.type="
  tiles = [
    { title = "Requests per second by status class", filter = "${local.m}\"run.googleapis.com/request_count\"", aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group = ["metric.labels.response_code_class"] },
    { title = "Error rate: 5xx requests per second", filter = "${local.m}\"run.googleapis.com/request_count\" AND metric.labels.response_code_class=\"5xx\"", aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group = [] },
    { title = "Latency P95 (ms)", filter = "${local.m}\"run.googleapis.com/request_latencies\"", aligner = "ALIGN_PERCENTILE_95", reducer = "REDUCE_MAX", group = [] },
    { title = "Latency P50 (ms)", filter = "${local.m}\"run.googleapis.com/request_latencies\"", aligner = "ALIGN_PERCENTILE_50", reducer = "REDUCE_MAX", group = [] },
    { title = "Health: container instances (active / idle)", filter = "${local.m}\"run.googleapis.com/container/instance_count\"", aligner = "ALIGN_MEAN", reducer = "REDUCE_SUM", group = ["metric.labels.state"] },
    { title = "CPU utilisation P95", filter = "${local.m}\"run.googleapis.com/container/cpu/utilizations\"", aligner = "ALIGN_PERCENTILE_95", reducer = "REDUCE_MAX", group = [] },
    { title = "Memory utilisation P95", filter = "${local.m}\"run.googleapis.com/container/memory/utilizations\"", aligner = "ALIGN_PERCENTILE_95", reducer = "REDUCE_MAX", group = [] },
    { title = "Application ERROR log entries per second", filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.app_errors.name}\"", aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group = [] },
  ]
}

resource "google_monitoring_dashboard" "main" {
  dashboard_json = jsonencode({
    displayName = "trebol-poc: service overview"
    mosaicLayout = {
      columns = 12
      tiles = [for i, t in local.tiles : {
        xPos   = (i % 2) * 6
        yPos   = floor(i / 2) * 4
        width  = 6
        height = 4
        widget = {
          title = t.title
          xyChart = {
            dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = t.filter
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = t.aligner
                    crossSeriesReducer = t.reducer
                    groupByFields      = t.group
                  }
                }
              }
            }]
            yAxis = { scale = "LINEAR" }
          }
        }
      }]
    }
  })
}

output "dashboard_name" {
  value = google_monitoring_dashboard.main.id
}