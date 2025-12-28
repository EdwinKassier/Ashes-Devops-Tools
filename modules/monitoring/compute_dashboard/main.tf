# -----------------------------------------------------------------------------
# Unified Compute Dashboard Module
# Creates a Cloud Monitoring dashboard for Cloud Run and Cloud Functions
# -----------------------------------------------------------------------------

locals {
  # Cloud Run XY Chart: Request Count by Response Code Class
  cloud_run_request_count_tile = {
    xPos   = 0
    yPos   = 8
    width  = 24
    height = 12
    widget = {
      title = "Cloud Run - Request Count by Status"
      xyChart = {
        dataSets = [
          {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\""
                aggregation = {
                  alignmentPeriod    = "60s"
                  perSeriesAligner   = "ALIGN_RATE"
                  crossSeriesReducer = "REDUCE_SUM"
                  groupByFields      = ["metric.label.response_code_class"]
                }
              }
            }
            plotType       = "STACKED_AREA"
            legendTemplate = "$${metric.labels.response_code_class}"
          }
        ]
        yAxis = {
          label = "Requests/sec"
          scale = "LINEAR"
        }
        chartOptions = {
          mode = "COLOR"
        }
      }
    }
  }

  # Cloud Run XY Chart: Request Latency (p50, p95, p99)
  cloud_run_latency_tile = {
    xPos   = 0
    yPos   = 24
    width  = 24
    height = 12
    widget = {
      title = "Cloud Run - Request Latency"
      xyChart = {
        dataSets = [
          {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_latencies\""
                aggregation = {
                  alignmentPeriod  = "60s"
                  perSeriesAligner = "ALIGN_PERCENTILE_50"
                }
              }
            }
            plotType       = "LINE"
            legendTemplate = "p50"
          },
          {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_latencies\""
                aggregation = {
                  alignmentPeriod  = "60s"
                  perSeriesAligner = "ALIGN_PERCENTILE_95"
                }
              }
            }
            plotType       = "LINE"
            legendTemplate = "p95"
          },
          {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_latencies\""
                aggregation = {
                  alignmentPeriod  = "60s"
                  perSeriesAligner = "ALIGN_PERCENTILE_99"
                }
              }
            }
            plotType       = "LINE"
            legendTemplate = "p99"
          }
        ]
        yAxis = {
          label = "Latency (ms)"
          scale = "LINEAR"
        }
        chartOptions = {
          mode = "COLOR"
        }
      }
    }
  }

  # Cloud Run XY Chart: CPU Utilization
  cloud_run_cpu_tile = {
    xPos   = 0
    yPos   = 40
    width  = 24
    height = 12
    widget = {
      title = "Cloud Run - CPU Utilization"
      xyChart = {
        dataSets = [
          {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/cpu/utilizations\""
                aggregation = {
                  alignmentPeriod    = "60s"
                  perSeriesAligner   = "ALIGN_PERCENTILE_99"
                  crossSeriesReducer = "REDUCE_MEAN"
                  groupByFields      = ["resource.label.service_name"]
                }
              }
            }
            plotType       = "LINE"
            legendTemplate = "$${resource.labels.service_name}"
          }
        ]
        yAxis = {
          label = "CPU Utilization"
          scale = "LINEAR"
        }
        chartOptions = {
          mode = "COLOR"
        }
      }
    }
  }

  # Cloud Run XY Chart: Memory Utilization
  cloud_run_memory_tile = {
    xPos   = 24
    yPos   = 40
    width  = 24
    height = 12
    widget = {
      title = "Cloud Run - Memory Utilization"
      xyChart = {
        dataSets = [
          {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/memory/utilizations\""
                aggregation = {
                  alignmentPeriod    = "60s"
                  perSeriesAligner   = "ALIGN_PERCENTILE_99"
                  crossSeriesReducer = "REDUCE_MEAN"
                  groupByFields      = ["resource.label.service_name"]
                }
              }
            }
            plotType       = "LINE"
            legendTemplate = "$${resource.labels.service_name}"
          }
        ]
        yAxis = {
          label = "Memory Utilization"
          scale = "LINEAR"
        }
        chartOptions = {
          mode = "COLOR"
        }
      }
    }
  }

  # Cloud Run XY Chart: Container Startup Latency (Cold Starts)
  cloud_run_startup_tile = {
    xPos   = 24
    yPos   = 24
    width  = 24
    height = 12
    widget = {
      title = "Cloud Run - Container Startup Latency (Cold Starts)"
      xyChart = {
        dataSets = [
          {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/startup_latencies\""
                aggregation = {
                  alignmentPeriod    = "60s"
                  perSeriesAligner   = "ALIGN_PERCENTILE_99"
                  crossSeriesReducer = "REDUCE_MEAN"
                  groupByFields      = ["resource.label.service_name"]
                }
              }
            }
            plotType       = "LINE"
            legendTemplate = "$${resource.labels.service_name}"
          }
        ]
        yAxis = {
          label = "Startup Latency (ms)"
          scale = "LINEAR"
        }
        chartOptions = {
          mode = "COLOR"
        }
      }
    }
  }

  # Cloud Run XY Chart: Billable Instance Time
  cloud_run_billing_tile = {
    xPos   = 0
    yPos   = 56
    width  = 24
    height = 12
    widget = {
      title = "Cloud Run - Billable Instance Time"
      xyChart = {
        dataSets = [
          {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/billable_instance_time\""
                aggregation = {
                  alignmentPeriod    = "60s"
                  perSeriesAligner   = "ALIGN_RATE"
                  crossSeriesReducer = "REDUCE_SUM"
                  groupByFields      = ["resource.label.service_name"]
                }
              }
            }
            plotType       = "STACKED_AREA"
            legendTemplate = "$${resource.labels.service_name}"
          }
        ]
        yAxis = {
          label = "Instance Seconds/sec"
          scale = "LINEAR"
        }
        chartOptions = {
          mode = "COLOR"
        }
      }
    }
  }

  # Cloud Run Scorecard: Instance Count
  cloud_run_instances_scorecard = {
    xPos   = 0
    yPos   = 0
    width  = 12
    height = 8
    widget = {
      title = "Cloud Run Instances"
      scorecard = {
        timeSeriesQuery = {
          timeSeriesFilter = {
            filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/instance_count\""
            aggregation = {
              alignmentPeriod    = "60s"
              perSeriesAligner   = "ALIGN_MEAN"
              crossSeriesReducer = "REDUCE_SUM"
            }
          }
        }
      }
    }
  }

  # Cloud Functions Tiles (Gen1)
  cloud_functions_execution_tile = {
    xPos   = 24
    yPos   = 8
    width  = 24
    height = 12
    widget = {
      title = "Cloud Functions - Execution Count by Status"
      xyChart = {
        dataSets = [
          {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\""
                aggregation = {
                  alignmentPeriod    = "60s"
                  perSeriesAligner   = "ALIGN_RATE"
                  crossSeriesReducer = "REDUCE_SUM"
                  groupByFields      = ["metric.label.status"]
                }
              }
            }
            plotType       = "STACKED_AREA"
            legendTemplate = "$${metric.labels.status}"
          }
        ]
        yAxis = {
          label = "Executions/sec"
          scale = "LINEAR"
        }
        chartOptions = {
          mode = "COLOR"
        }
      }
    }
  }

  cloud_functions_latency_tile = {
    xPos   = 24
    yPos   = 56
    width  = 24
    height = 12
    widget = {
      title = "Cloud Functions - Execution Time"
      xyChart = {
        dataSets = [
          {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_times\""
                aggregation = {
                  alignmentPeriod  = "60s"
                  perSeriesAligner = "ALIGN_PERCENTILE_50"
                }
              }
            }
            plotType       = "LINE"
            legendTemplate = "p50"
          },
          {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_times\""
                aggregation = {
                  alignmentPeriod  = "60s"
                  perSeriesAligner = "ALIGN_PERCENTILE_95"
                }
              }
            }
            plotType       = "LINE"
            legendTemplate = "p95"
          },
          {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_times\""
                aggregation = {
                  alignmentPeriod  = "60s"
                  perSeriesAligner = "ALIGN_PERCENTILE_99"
                }
              }
            }
            plotType       = "LINE"
            legendTemplate = "p99"
          }
        ]
        yAxis = {
          label = "Execution Time (ns)"
          scale = "LINEAR"
        }
        chartOptions = {
          mode = "COLOR"
        }
      }
    }
  }

  cloud_functions_instances_scorecard = {
    xPos   = 12
    yPos   = 0
    width  = 12
    height = 8
    widget = {
      title = "Cloud Functions Active Instances"
      scorecard = {
        timeSeriesQuery = {
          timeSeriesFilter = {
            filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/active_instances\""
            aggregation = {
              alignmentPeriod    = "60s"
              perSeriesAligner   = "ALIGN_MEAN"
              crossSeriesReducer = "REDUCE_SUM"
            }
          }
        }
      }
    }
  }

  # Text Widget for section header
  header_tile = {
    xPos   = 24
    yPos   = 0
    width  = 24
    height = 8
    widget = {
      title = ""
      text = {
        content = "## 📊 Unified Compute Dashboard\n\nMonitoring Cloud Run and Cloud Functions across all services.\n\n**Tip:** Look for 5xx spikes in request charts and high p99 latencies."
        format  = "MARKDOWN"
      }
    }
  }

  # Build tiles array based on configuration
  cloud_run_tiles = [
    local.cloud_run_instances_scorecard,
    local.cloud_run_request_count_tile,
    local.cloud_run_latency_tile,
    local.cloud_run_cpu_tile,
    local.cloud_run_memory_tile,
    local.cloud_run_startup_tile,
    local.cloud_run_billing_tile,
    local.header_tile,
  ]

  cloud_functions_tiles = var.include_gen1_functions ? tolist([
    local.cloud_functions_instances_scorecard,
    local.cloud_functions_execution_tile,
    local.cloud_functions_latency_tile,
  ]) : tolist([])

  dashboard_tiles = concat(local.cloud_run_tiles, local.cloud_functions_tiles)
}

# -----------------------------------------------------------------------------
# Monitoring Dashboard Resource
# -----------------------------------------------------------------------------

resource "google_monitoring_dashboard" "compute_dashboard" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = var.dashboard_display_name
    mosaicLayout = {
      columns = 48
      tiles   = local.dashboard_tiles
    }
  })

  lifecycle {
    # Workaround for known perma-diff issue with dashboard_json
    # The API may return slightly different JSON than what was sent
    ignore_changes = [dashboard_json]
  }
}
