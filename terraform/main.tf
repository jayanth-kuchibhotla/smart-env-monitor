# ─── Provider ────────────────────────────────────────────────
terraform {
    required_providers {
      aws = {
        source  = "hashicorp/aws"
        version = "~> 5.0"
      }
    }
    required_version = ">= 1.0"
}

provider "aws" {
    region = var.aws_region
    access_key = var.aws_access_key
    secret_key = var.aws_secret_key
}

# ─── IoT Core endpoint (data source) ─────────────────────────
data "aws_iot_endpoint" "current" {
    endpoint_type = "iot:Data-ATS"
}

# ─── IoT Core Thing ──────────────────────────────────────────
resource "aws_iot_thing" "esp32" {
    name = "esp32-env-monitor"
}

# ─── IoT Core Policy ─────────────────────────────────────────
resource "aws_iot_policy" "esp32-policy" {
    name = "esp32-env-policy"

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect   = "Allow"
                Action   = "iot:Connect"
                Resource = "arn:aws:iot:${var.aws_region}:${var.aws_account_id}:client/esp32-env-monitor"
            },
            {
                Effect   = "Allow"
                Action   = "iot:Publish"
                Resource = "arn:aws:iot:${var.aws_region}:${var.aws_account_id}:topic/home/envmonitor/*"
            },
            {
                Effect = "Allow"
                Action = [
                    "iot:Subscribe",
                    "iot:Receive"
                ]
                Resource = "arn:aws:iot:${var.aws_region}:${var.aws_account_id}:topicfilter/home/envmonitor/*"
            }
        ]
    })
}

# ─── IoT Core Rule ───────────────────────────────────────────
resource "aws_iot_topic_rule" "esp32_rule" {
    name        = "esp32_to_lambda_rule"
    enabled     = true
    sql         = "SELECT * FROM 'home/envmonitor/monitoring-device'"
    sql_version = "2016-03-23"

    lambda {
        function_arn = aws_lambda_function.process_readings.arn
    }
}

# ─── Lambda permission for IoT Core ──────────────────────────
resource "aws_lambda_permission" "iot_invoke_lambda" {
    statement_id  = "AllowIoTInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.process_readings.function_name
    principal     = "iot.amazonaws.com"
    source_arn    = aws_iot_topic_rule.esp32_rule.arn
}

# ─── DynamoDB Table ──────────────────────────────────────────
resource "aws_dynamodb_table" "sensor_readings" {
    name         = "SensorReadings"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "device_id"
    range_key    = "timestamp"

    attribute {
        name = "device_id"
        type = "S"
    }

    attribute {
        name = "timestamp"
        type = "S"
    }

    ttl {
        attribute_name = "expiry_time"
        enabled        = true
    }
}

# ─── IAM Role for Lambda ──────────────────────────────────────
resource "aws_iam_role" "lambda_role" {
    name = "esp32-lambda-role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action    = "sts:AssumeRole"
                Effect    = "Allow"
                Principal = {
                    Service = "lambda.amazonaws.com"
                }
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ─── Lambda Function ─────────────────────────────────────────
resource "aws_lambda_function" "process_readings" {
    filename         = "lambda_function.zip"
    function_name    = "esp32-process-readings"
    role             = aws_iam_role.lambda_role.arn
    handler          = "lambda_function.lambda_handler"
    runtime          = "python3.12"
    source_code_hash = filebase64sha256("lambda_function.zip")
    timeout          = 10
    memory_size      = 128

    depends_on       = [
        aws_iam_role_policy_attachment.lambda_dynamodb,
        aws_iam_role_policy_attachment.lambda_cloudwatch,
        aws_iam_role_policy_attachment.lambda_basic
    ]
}

# ─── SNS Topic ───────────────────────────────────────────────
resource "aws_sns_topic" "env_alerts" {
    name = "esp32-env-alerts"
}

resource "aws_sns_topic_subscription" "email_alert" {
    topic_arn = aws_sns_topic.env_alerts.arn
    protocol  = "email"
    endpoint  = var.alert_email
}

# ─── CloudWatch Alarm ────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "high_temp" {
    alarm_name          = "ZoneA-HighTemp-Alarm"
    comparison_operator = "GreaterThanThreshold"
    evaluation_periods  = 1
    metric_name         = "ZoneATemp"
    namespace           = "ESP32EnvMonitor"
    period              = 300
    statistic           = "Average"
    threshold           = 30.0
    alarm_description   = "Zone A temperature exceeded 30°C"
    alarm_actions       = [aws_sns_topic.env_alerts.arn]
    treat_missing_data  = "missing"
}
