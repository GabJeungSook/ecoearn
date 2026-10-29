// EcoEarn - load cell + HX711 test and calibration
//
// Prints the weight on the load cell twice a second. Type in the Serial Monitor
// (line ending "New Line"):
//   t        zero the scale (nothing on it)
//   c 74     calibrate: put a known weight on it first, then type its grams
// The calibration is saved in the ESP32's flash, so it survives a restart.
//
// Wiring (ESP32 30-pin board):
//   HX711 GND -> GND   DT -> D16   SCK -> D17   (labelled RX2/TX2 on some boards)   VCC -> 3V3
//   Load cell -> HX711: red E+, black E-, white A-, green A+

#include <HX711.h>
#include <Preferences.h>

const int HX711_DT_PIN = 16;
const int HX711_SCK_PIN = 17;

HX711 scale;
Preferences settings;
float gramsFactor = 0; // raw counts per gram; 0 = not calibrated yet
unsigned long lastPrint = 0;

void zero() {
  scale.tare(20);
  Serial.println("Scale zeroed.");
}

void calibrate(float knownGrams) {
  if (knownGrams <= 0) {
    Serial.println("Type the weight in grams, e.g.  c 74");
    return;
  }
  long counts = scale.read_average(20) - scale.get_offset();
  // A tiny change means nothing (or almost nothing) is on the scale.
  if (labs(counts) < 1000) {
    Serial.println("Hardly any weight detected. Zero with t first, then put the weight on and try again.");
    return;
  }
  // A negative factor is fine: it just means white/green are the other way round.
  gramsFactor = counts / knownGrams;
  settings.putFloat("factor", gramsFactor);
  Serial.printf("Calibrated: %.2f counts per gram (saved).\n", gramsFactor);
}

void handleCommand(String line) {
  line.trim();
  if (line == "t") zero();
  else if (line.startsWith("c")) calibrate(line.substring(1).toFloat());
  else if (line.length() > 0) Serial.println("Commands: t = zero, c <grams> = calibrate");
}

void setup() {
  Serial.begin(115200);
  delay(500);
  scale.begin(HX711_DT_PIN, HX711_SCK_PIN);
  settings.begin("scale");
  gramsFactor = settings.getFloat("factor", 0);

  Serial.println();
  if (!scale.wait_ready_timeout(2000)) {
    Serial.println("HX711 NOT answering. Check the 4 wires (GND, DT->D16, SCK->D17, VCC->3V3).");
  } else {
    Serial.println("HX711 found. Keep the scale empty while it zeroes...");
    zero();
  }
  if (gramsFactor == 0) Serial.println("Not calibrated yet: put a known weight on, then type  c <grams>");
  else Serial.printf("Using saved calibration: %.2f counts per gram.\n", gramsFactor);
}

void loop() {
  if (Serial.available()) handleCommand(Serial.readStringUntil('\n'));

  if (millis() - lastPrint < 500) return;
  lastPrint = millis();

  if (!scale.wait_ready_timeout(1000)) {
    Serial.println("HX711 stopped answering (loose wire?).");
    return;
  }
  long counts = scale.read_average(5) - scale.get_offset();
  if (gramsFactor == 0) Serial.printf("raw: %ld\n", counts);
  else Serial.printf("raw: %ld   weight: %.1f g\n", counts, counts / gramsFactor);
}
