# Second monitoring component, cloud-native and independent of the Prometheus
# stack running ON the instance: CloudWatch alarms -> SNS -> your e-mail.
#
# Why this exists alongside Prometheus/Alertmanager:
#   * it keeps working even if the monitoring instance itself dies (the
#     in-instance stack cannot alert on its own death),
#   * it delivers to a real notification channel (e-mail) with no SMTP
#     credentials stored anywhere,
#   * it satisfies "at least two monitoring components" with two genuinely
#     different mechanisms rather than two views of the same data.
#
# State is LOCAL and separate from ../../11-network/terraform on purpose --
# this only reads that stack's outputs, it never modifies it.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
  profile = "oleksandrshekera"
}

# Read the instances created by 11-network without owning them.
data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "${path.module}/../../../11-network/terraform/terraform.tfstate"
  }
}

locals {
  monitoring_instance_id = data.terraform_remote_state.network.outputs.monitoring_instance_id
  web_instance_id        = data.terraform_remote_state.network.outputs.web_instance_id
}

# ---------------------------------------------------------------- notification
resource "aws_sns_topic" "alerts" {
  name = "${var.project}-container-alerts"

  tags = {
    Project    = "PeEx"
    Competency = "containers-observability"
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
  # NOTE: AWS sends a confirmation e-mail. The subscription stays
  # "pending confirmation" until you click the link -- alarms will not be
  # delivered before that. Confirming is a one-time manual step by design.
}

# --------------------------------------------------------------------- alarms
resource "aws_cloudwatch_metric_alarm" "monitoring_cpu" {
  alarm_name          = "${var.project}-monitoring-cpu-high"
  alarm_description   = "CPU on the monitoring instance stayed above ${var.cpu_threshold}% -- the container stack may be in a runaway loop."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = local.monitoring_instance_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  # Two evaluation periods of 5 minutes: long enough that a build or an image
  # pull does not page anyone, short enough to catch a real runaway.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "web_cpu" {
  alarm_name          = "${var.project}-web-cpu-high"
  alarm_description   = "CPU on the web instance stayed above ${var.cpu_threshold}%."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = local.web_instance_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# Instance-level health: this is the alarm the in-instance Prometheus stack
# structurally cannot raise about itself.
resource "aws_cloudwatch_metric_alarm" "monitoring_status_check" {
  alarm_name          = "${var.project}-monitoring-status-check-failed"
  alarm_description   = "EC2 status check failed on the monitoring instance -- the host or its network is unhealthy."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = local.monitoring_instance_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
