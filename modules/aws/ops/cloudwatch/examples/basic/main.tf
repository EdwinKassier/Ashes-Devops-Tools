# Basic working example for the aws/cloudwatch module.
# Creates two metric alarms for an application load balancer (5XX errors and
# target response time), a KMS-encrypted SNS topic wired as the alarm/OK action
# for both, and a small CloudWatch dashboard. Run `terraform init && terraform
# validate` here to check it.
#
# The KMS key ARN and load balancer dimension are placeholders: replace them
# with your own.

module "cloudwatch" {
  source = "../../"

  name_prefix = "dev-orders"

  create_sns_topic      = true
  sns_kms_master_key_id = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"

  alarms = {
    alb-5xx = {
      namespace           = "AWS/ApplicationELB"
      metric_name         = "HTTPCode_ELB_5XX_Count"
      statistic           = "Sum"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 10
      period              = 300
      evaluation_periods  = 2
      dimensions = {
        LoadBalancer = "app/dev-app-alb/0123456789abcdef"
      }
      alarm_description = "ALB returned more than 10 5XX responses in 5 minutes."
    }
    alb-latency = {
      namespace           = "AWS/ApplicationELB"
      metric_name         = "TargetResponseTime"
      comparison_operator = "GreaterThanThreshold"
      threshold           = 1
      period              = 300
      evaluation_periods  = 3
      datapoints_to_alarm = 2
      dimensions = {
        LoadBalancer = "app/dev-app-alb/0123456789abcdef"
      }
      alarm_description = "Average target response time above 1 second."
    }
  }

  enable_dashboard = true
  dashboard_widgets = [
    {
      type   = "metric"
      x      = 0
      y      = 0
      width  = 12
      height = 6
      properties = {
        title  = "ALB 5XX count"
        region = "eu-west-2"
        stat   = "Sum"
        period = 300
        metrics = [
          ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", "app/dev-app-alb/0123456789abcdef"],
        ]
      }
    },
  ]

  tags = {
    environment = "dev"
  }
}
