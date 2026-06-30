// ─── Libraries ──────────────────────────────────────
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <DHT.h>
#include <secrets.h>

// ─── AWS IoT endpoint ───────────────────────────────
#define AWS_IOT_PORT     8883

// ─── MQTT topic ─────────────────────────────────────
#define MQTT_TOPIC       "home/envmonitor/monitoring-device"
#define CLIENT_ID        "esp32-env-monitor"

// ─── Sensor pins ────────────────────────────────────
#define DHTPIN_A 4
#define DHTPIN_B 5
#define DHTTYPE DHT11
#define TRIG_PIN 18
#define ECHO_PIN 19
#define RELAY1_PIN 21
#define RELAY2_PIN 22

// ─── Thresholds ─────────────────────────────────────
#define TEMP_THRESHOLD 30.0
#define HUM_THRESHOLD  70.0

// ─── Globals ────────────────────────────────────────
WiFiClientSecure net;
PubSubClient mqtt(net);
DHT dhtA(DHTPIN_A, DHTTYPE);
DHT dhtB(DHTPIN_B, DHTTYPE);

// ─── WiFi connect ───────────────────────────────────
void connectWiFi() {
  Serial.print("[WiFi] Connecting to ");
  Serial.println(WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\n[WiFi] Connected. IP: ");
  Serial.println(WiFi.localIP());
}

// ─── MQTT connect ───────────────────────────────────
void connectMQTT() {
  net.setCACert(AWS_ROOT_CA);
  net.setCertificate(DEVICE_CERT);
  net.setPrivateKey(DEVICE_KEY);
  mqtt.setServer(AWS_IOT_ENDPOINT, AWS_IOT_PORT);
  mqtt.setBufferSize(512);

  Serial.print("[MQTT] Connecting to AWS IoT...");
  while (!mqtt.connected()) {
    if(mqtt.connect(CLIENT_ID)){
      Serial.println(" connected.");
    } else {
      Serial.print(" failed, rc=");
      Serial.print(mqtt.state());
      Serial.println(". Attempting to reconnect in 5s...");
      delay(5000);
    }
  }
}

// ─── Ultrasonic ─────────────────────────────────────
float readDistance() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  long duration = pulseIn(ECHO_PIN, HIGH, 30000);
  if (duration == 0) return -1;
  return (duration * 0.0343) / 2;
}

// ─── Setup ──────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  dhtA.begin();
  dhtB.begin();
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(RELAY1_PIN, OUTPUT);
  pinMode(RELAY2_PIN, OUTPUT);
  digitalWrite(RELAY1_PIN, LOW);
  digitalWrite(RELAY2_PIN, LOW);

  connectWiFi();
  connectMQTT();
}

// ─── Loop ───────────────────────────────────────────
void loop() {
  if(!mqtt.connected()) connectMQTT();
  mqtt.loop();

  delay(10000); //publish every 10 seconds

  float tempA = dhtA.readTemperature();
  float humA  = dhtA.readHumidity();
  float tempB = dhtB.readTemperature();
  float humB  = dhtB.readHumidity();
  float dist  = readDistance();

  bool relay1on = (!isnan(tempA) && tempA > TEMP_THRESHOLD);
  bool relay2on = (!isnan(humB)  && humB  > HUM_THRESHOLD);

  digitalWrite(RELAY1_PIN, relay1on ? HIGH : LOW);
  digitalWrite(RELAY2_PIN, relay2on ? HIGH : LOW);

  // Build JSON payload
  char payload[256];
  snprintf(payload, sizeof(payload),
    "{\"device\":\"esp32-env-monitor\","
    "\"zoneA\":{\"temp\":%.1f,\"humidity\":%.1f},"
    "\"zoneB\":{\"temp\":%.1f,\"humidity\":%.1f},"
    "\"distance_cm\":%.1f,"
    "\"relay1\":\"%s\","
    "\"relay2\":\"%s\"}",
    tempA, humA, tempB, humB, dist,
    relay1on ? "ON" : "OFF",
    relay2on ? "ON" : "OFF"
  );

  if(mqtt.publish(MQTT_TOPIC, payload)) {
    Serial.println("[MQTT] Published:");
    Serial.println(payload);
  } else {
    Serial.println("[MQTT] Publish failed");
  }
  
  Serial.println("------ Sensor Readings ------");
  Serial.print("[Zone A] Temp: "); Serial.print(tempA, 1);
  Serial.print(" C  |  Humidity: "); Serial.print(humA, 1); Serial.println(" %");
  Serial.print("[Zone B] Temp: "); Serial.print(tempB, 1);
  Serial.print(" C  |  Humidity: "); Serial.print(humB, 1); Serial.println(" %");
  Serial.print("[Ultrasonic] Distance: "); Serial.print(dist, 1); Serial.println(" cm");
  Serial.print("[Relay 1 - Fan]        "); Serial.println(relay1on ? "ON" : "OFF");
  Serial.print("[Relay 2 - Humidifier] "); Serial.println(relay2on ? "ON" : "OFF");
  Serial.println("-----------------------------\n");
}