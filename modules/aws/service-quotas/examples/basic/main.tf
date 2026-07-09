# Basic working example for the aws/service-quotas module.
# Files one quota-increase request and provisions its AWS/Usage alarm, routed
# to a security-notifications SNS topic.
# Run `terraform init && terraform validate` here.

module "service_quotas" {
  source = "../../"

  enable_service_quotas = true

  quota_increases = {
    ec2-standard-vcpus = {
      service_code = "ec2"
      quota_code   = "L-1216C47A"
      value        = 256
    }
  }

  notifications_topic_arn = "arn:aws:sns:eu-west-2:111111111111:security-notifications"
}
