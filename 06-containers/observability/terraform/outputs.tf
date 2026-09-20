output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "subscription_status" {
  description = "Reminder: check your inbox and confirm the SNS subscription."
  value       = "Subscription for ${var.alert_email} created -- confirm it from the e-mail AWS sends, or no notification will arrive."
}

output "alarm_names" {
  value = [
    aws_cloudwatch_metric_alarm.monitoring_cpu.alarm_name,
    aws_cloudwatch_metric_alarm.web_cpu.alarm_name,
    aws_cloudwatch_metric_alarm.monitoring_status_check.alarm_name,
  ]
}
