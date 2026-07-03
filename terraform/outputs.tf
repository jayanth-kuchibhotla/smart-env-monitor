output "dynamodb_table_name" {
    description = "DynamoDB table name"
    value       = aws_dynamodb_table.sensor_readings.name
}

output "lambda_function_name" {
    description = "Lambda function name"
    value       = aws_lambda_function.process_readings.function_name
}

output "iot_core_endpoint" {
    description = "AWS IoT Core device data endpoint for ESP32 firmware"
    value       = data.aws_iot_endpoint.current.endpoint_address
}

output "cloudwatch_alarm_name" {
    description = "CloudWatch alarm name"
    value       = aws_cloudwatch_metric_alarm.high_temp.alarm_name
}

output "sns_topic_arn" {
    description = "SNS topic ARN"
    value       = aws_sns_topic.env_alerts.arn
}
