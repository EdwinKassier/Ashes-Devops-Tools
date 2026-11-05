# Variable validation tests for the aws/compute/ecs-fargate module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation, so these pass regardless of
# mock provider behaviour.

mock_provider "aws" {}

# Base set of valid required variables, shared by every run.
variables {
  name               = "orders-api"
  region             = "eu-west-2"
  family             = "orders-api"
  cluster_arn        = "arn:aws:ecs:eu-west-2:123456789012:cluster/app"
  container_image    = "123456789012.dkr.ecr.eu-west-2.amazonaws.com/orders:1.0.0"
  subnets            = ["subnet-0aaa", "subnet-0bbb"]
  security_group_ids = ["sg-0aaa"]
  execution_role_arn = "arn:aws:iam::123456789012:role/orders-exec"
  task_role_arn      = "arn:aws:iam::123456789012:role/orders-task"
}

run "defaults_accepted" {
  command = plan
}

run "invalid_cpu_rejected" {
  command = plan

  variables {
    cpu = 300 # not a valid Fargate CPU value
  }

  expect_failures = [var.cpu]
}

run "plaintext_secret_rejected" {
  command = plan

  # A plaintext valueFrom (not a Secrets Manager / SSM ARN) must be rejected so
  # secret material can never be embedded in the task definition.
  variables {
    container_secrets = [
      { name = "DB_PASSWORD", valueFrom = "hunter2" }
    ]
  }

  expect_failures = [var.container_secrets]
}

run "secret_arn_accepted" {
  command = plan

  variables {
    container_secrets = [
      { name = "DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:orders/db-AbCdEf" }
    ]
  }
}

run "bad_execution_role_arn_rejected" {
  command = plan

  variables {
    execution_role_arn = "not-an-arn"
  }

  expect_failures = [var.execution_role_arn]
}

run "invalid_target_group_arn_rejected" {
  command = plan

  variables {
    target_group_arn = "arn:aws:ecs:eu-west-2:123456789012:cluster/wrong"
  }

  expect_failures = [var.target_group_arn]
}
