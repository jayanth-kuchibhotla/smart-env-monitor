import json
import boto3
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('SensorReadings')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        device_id = event.get('device', 'unknown')
        timestamp = datetime.now(timezone.utc).isoformat()

        zone_a = event.get('zoneA', {})
        zone_b = event.get('zoneB', {})
        distance = event.get('distance_cm', None)
        relay1 = event.get('relay1', 'OFF')
        relay2 = event.get('relay2', 'OFF')

        # Write to DynamoDB
        table.put_item(Item={
            'device_id': device_id,
            'timestamp': timestamp,
            'zoneA_temp': str(zone_a.get('temp')),
            'zoneA_humidity': str(zone_a.get('humidity')),
            'zoneB_temp': str(zone_b.get('temp')),
            'zoneB_humidity': str(zone_b.get('humidity')),
            'distance_cm': str(distance),
            'relay1': relay1,
            'relay2': relay2
        })

        # Push custom metric to CloudWatch for alarm + Grafana
        cloudwatch.put_metric_data(
            Namespace='ESP32EnvMonitor',
            MetricData=[
                {'MetricName': 'ZoneATemp', 'Value': float(zone_a.get('temp', 0)), 'Unit': 'None'},
                {'MetricName': 'ZoneAHumidity', 'Value': float(zone_a.get('humidity', 0)), 'Unit': 'Percent'},
                {'MetricName': 'ZoneBTemp', 'Value': float(zone_b.get('temp', 0)), 'Unit': 'None'},
                {'MetricName': 'ZoneBHumidity', 'Value': float(zone_b.get('humidity', 0)), 'Unit': 'Percent'},
                {'MetricName': 'DistanceCM', 'Value': float(distance) if distance is not None else 0, 'Unit': 'None'}
            ]
        )

        return {
            'statusCode': 200,
            'body': json.dumps('Reading stored successfully')
        }

    except Exception as e:
        print(f"Error processing reading: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }