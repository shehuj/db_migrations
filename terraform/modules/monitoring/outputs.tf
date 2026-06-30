output "sns_topic_arn" {
  description = "ARN of the alarm SNS topic."
  value       = aws_sns_topic.alarms.arn
}
