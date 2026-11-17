// EcoEarn - ESP32 firmware
//
// One transaction: card tap -> crush + drain -> weigh -> points -> into bin.
// Every message to the laptop is one JSON object on its own line.
// Hardware that isn't connected yet is faked (see the FAKE_ switches in config.h).
// Lines starting with "# " are hints for a person reading the Serial Monitor;
// the laptop app ignores them because they aren't JSON.
//
// Commands from the laptop (one per line):
//   register   report the next card tap as a "scan" event instead of starting a
//              deposit (for assigning cards to students); ends after one card or 30 s
//   cancel     leave register mode
//   tare       zero the scale (it must be empty)
//   cal 74     calibrate: tare first, put a known weight on, then cal <its grams>
//   weigh      print the current weight (to check the calibration)
//   rate 10    points rate: 1 point per 10 g, saved in flash (the app sends it)
//   version    answer with the boot message (firmware version and rate)

#include "config.h"
#include <Preferences.h>

#if !FAKE_RFID
#include <SPI.h>
#include <MFRC522.h>
MFRC522 rfid(RFID_SDA_PIN, RFID_RST_PIN);
#endif

#if !FAKE_SCALE
#include <HX711.h>
HX711 scale;
float gramsFactor = 0;   // raw counts per gram (saved by "cal" or scale_test); 0 = not calibrated
#endif

const int WEIGH_FAILED = -1000;        // readWeightGrams() result when the scale can't weigh
const char* scaleProblem = nullptr;   // ...and why

// Pretend student cards, used while FAKE_RFID is 1.
const char* FAKE_UIDS[] = { "A3F29B11", "5C7E0D42", "91B4E6F3" };
const int FAKE_UID_COUNT = sizeof(FAKE_UIDS) / sizeof(FAKE_UIDS[0]);

unsigned long lastFakeTap = 0;   // used while FAKE_RFID is 1
int fakeBinLevel = 10;           // percent, used while FAKE_BIN_LEVEL is 1

bool registerMode = false;       // next card tap is only read, not a deposit
unsigned long registerStarted = 0;

// ---------- Messages to the laptop ----------

// Points rate: 1 point per this many grams. Set by the laptop ("rate" command)
// and kept in flash, so the machine uses it even without the laptop.
int gramsPerPoint = GRAMS_PER_POINT;

void sendBoot() {
  Serial.printf("{\"event\":\"boot\",\"version\":\"%s\",\"grams_per_point\":%d}\n",
                FIRMWARE_VERSION, gramsPerPoint);
}

void sendCard(const String& uid) {
  Serial.printf("{\"event\":\"card\",\"uid\":\"%s\"}\n", uid.c_str());
}

// The machine has started a step of the deposit, so screens can show what it's
// really doing. stage: "ready" (zeroing the scale), "crushing", "draining",
// "dropping" (trapdoor), "weighing", "tipping" (into the bin). expectedMs is a
// typical duration for progress bars (0 = unknown); the step ends when the next
// stage or the result arrives.
void sendStage(const String& uid, const char* stage, unsigned long expectedMs) {
  Serial.printf("{\"event\":\"stage\",\"uid\":\"%s\",\"stage\":\"%s\",\"ms\":%lu}\n", uid.c_str(), stage, expectedMs);
}

void sendScan(const String& uid) {
  Serial.printf("{\"event\":\"scan\",\"uid\":\"%s\"}\n", uid.c_str());
}

void sendWeight(const String& uid, int grams, int points) {
  Serial.printf("{\"event\":\"weight\",\"uid\":\"%s\",\"grams\":%d,\"points\":%d,\"grams_per_point\":%d}\n",
                uid.c_str(), grams, points, gramsPerPoint);
}

// reason: "bin_full", "mechanism", "no_item" or "too_heavy"
// detail (optional) says more about a "mechanism" reject, e.g. "scale_not_calibrated".
void sendReject(const String& uid, const char* reason, int grams, const char* detail = nullptr) {
  Serial.printf("{\"event\":\"reject\",\"uid\":\"%s\",\"reason\":\"%s\",\"grams\":%d",
                uid.c_str(), reason, grams);
  if (detail) Serial.printf(",\"detail\":\"%s\"", detail);
  Serial.println("}");
}

void sendBin(int level) {
  Serial.printf("{\"event\":\"bin\",\"level\":%d}\n", level);
}

// ---------- Hardware steps (fake or real) ----------

// Returns the tapped card's UID, or "" if no card is there.
String readCard() {
#if FAKE_RFID
  if (millis() - lastFakeTap < FAKE_TAP_EVERY_MS) return "";
  lastFakeTap = millis();
  return FAKE_UIDS[random(FAKE_UID_COUNT)];
#else
  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) return "";
  String uid;
  for (byte i = 0; i < rfid.uid.size; i++) {
    char hex[3];
    sprintf(hex, "%02X", rfid.uid.uidByte[i]);
    uid += hex;
  }
  rfid.PICC_HaltA();   // the same card must be taken away and tapped again
  return uid;
#endif
}

// Mechanism steps 2-5: bottle detected, lid closed, crush, drain, trapdoor opens.
// Returns false if something went wrong (lid opened, motion timed out).
// Each step is its own function, fake or real, so runTransaction() can announce
// the steps the same way whichever hardware is fitted.

// Step 3: the actuator extends (spikes pierce, plate crushes) and retracts.
bool crush() {
#if FAKE_MECHANISM
#if !FAKE_SCALE
  Serial.println("# Put the item on the scale now.");
#endif
  delay(CRUSH_EXPECTED_MS);   // pretend: actuator extends and retracts
  return true;
#else
  #error "Real actuator is not written yet. Set FAKE_MECHANISM to 1 in config.h."
#endif
}

// Step 4: leftover liquid drains out of the chamber (same wait with or without hardware).
void drain() {
  delay(DRAIN_TIME_MS);
}

// Step 5: the trapdoor servo opens, the bottle falls onto the scale, the door closes.
bool dropToScale() {
#if FAKE_MECHANISM
  delay(DROP_EXPECTED_MS);    // pretend: trapdoor opens and closes
  return true;
#else
  #error "Real trapdoor is not written yet. Set FAKE_MECHANISM to 1 in config.h."
#endif
}

#if !FAKE_SCALE
// One reading in grams averaged over `samples` HX711 conversions (10 per second),
// or NAN if the HX711 doesn't answer.
float readGramsOnce(int samples = 3) {
  if (!scale.wait_ready_timeout(500)) return NAN;
  return (scale.read_average(samples) - scale.get_offset()) / gramsFactor;
}

// Zeroes the scale, but only if it is close to empty, so an item left on the
// tray isn't zeroed away.
void rezeroIfEmpty() {
  float grams = readGramsOnce();
  if (!isnan(grams) && fabs(grams) < MIN_ITEM_GRAMS) scale.tare(10);
}

// Zeroes the scale once it is steady: right after a card tap the table can
// still be shaking from the student's hand. Waits for 3 readings in a row
// within STABLE_GRAMS (at most ZERO_SETTLE_MS), then zeroes. The status LED blinks
// meanwhile and turns solid when the item may go on.
void zeroWhenSteady() {
  if (gramsFactor == 0) return;
  float previous = NAN, beforeThat = NAN;
  unsigned long start = millis();
  while (millis() - start < ZERO_SETTLE_MS) {
    digitalWrite(STATUS_LED_PIN, !digitalRead(STATUS_LED_PIN));
    float grams = readGramsOnce(SAMPLES_PER_READING);
    if (isnan(grams)) continue;
    if (fabs(grams - previous) <= STABLE_GRAMS && fabs(grams - beforeThat) <= STABLE_GRAMS &&
        fabs(previous - beforeThat) <= STABLE_GRAMS) break;
    beforeThat = previous;
    previous = grams;
  }
  scale.tare(10);
  digitalWrite(STATUS_LED_PIN, HIGH);
}
#endif

// Mechanism step 6: stable weight of the crushed bottle, in grams.
// Returns WEIGH_FAILED if the scale can't give a settled reading (not calibrated,
// not answering, or the tray keeps moving).
int readWeightGrams() {
#if FAKE_SCALE
  if (random(8) == 0) return random(90, 150);   // now and then, a too-heavy item
  return random(12, 45);                        // typical crushed bottle
#else
  if (gramsFactor == 0) {
    scaleProblem = "scale_not_calibrated";
    return WEIGH_FAILED;
  }
  // Wait until STABLE_READINGS readings in a row stay within STABLE_GRAMS;
  // the weight is their average. A reading the HX711 misses (e.g. a wire
  // flickering) is skipped rather than failing the whole weighing.
  float recent[STABLE_READINGS];
  int count = 0;
  bool answered = false;
  unsigned long start = millis();
  while (millis() - start < WEIGH_TIMEOUT_MS) {
    float grams = readGramsOnce(SAMPLES_PER_READING);
    if (isnan(grams)) continue;
    answered = true;
    recent[count % STABLE_READINGS] = grams;
    count++;
    if (count < STABLE_READINGS) continue;

    float low = recent[0], high = recent[0], sum = 0;
    for (float g : recent) {
      low = min(low, g);
      high = max(high, g);
      sum += g;
    }
    // Slight drift below zero on an empty tray is still "nothing", not a failure.
    if (high - low <= STABLE_GRAMS) return max(0L, lround(sum / STABLE_READINGS));
  }
  scaleProblem = answered ? "scale_unsettled" : "scale_not_answering";
  return WEIGH_FAILED;
#endif
}

// Mechanism step 8: tray tilts the bottle into the storage bin, scale re-zeroes.
void tipIntoBin() {
#if FAKE_MECHANISM
#if FAKE_SCALE
  delay(500);
#else
  // No tray servo yet: wait for a person to take the item off.
  Serial.println("# Take the item off the scale.");
  unsigned long start = millis();
  while (millis() - start < REMOVE_ITEM_MS) {
    digitalWrite(STATUS_LED_PIN, (millis() / 500) % 2);   // blinking again = take it off
    float grams = readGramsOnce();
    if (!isnan(grams) && grams < MIN_ITEM_GRAMS) break;
  }
  rezeroIfEmpty();
#endif
#if FAKE_BIN_LEVEL
  fakeBinLevel += random(4, 9);
#endif
#else
  #error "Real mechanism is not written yet. Set FAKE_MECHANISM to 1 in config.h."
#endif
}

// Mechanism step 9: how full the storage bin is, 0-100 percent.
int readBinLevel() {
#if FAKE_BIN_LEVEL
  return min(fakeBinLevel, 100);
#else
  #error "Real bin sensor is not written yet. Set FAKE_BIN_LEVEL to 1 in config.h."
#endif
}

// ---------- Point allocation ----------

int pointsForGrams(int grams) {
  return grams / gramsPerPoint;
}

// ---------- One full transaction ----------

void runTransaction(const String& uid) {
  if (readBinLevel() >= BIN_FULL_PERCENT) {
    sendReject(uid, "bin_full", 0);
#if FAKE_BIN_LEVEL
    fakeBinLevel = 5;   // pretend a staff member empties the bin
#endif
    return;
  }

  sendStage(uid, "ready", ZERO_SETTLE_MS);
#if !FAKE_SCALE
  // The weighing tray is empty at the card tap (the bottle is still in the
  // crushing chamber), so zero here: earlier drift can't add phantom grams.
  zeroWhenSteady();
#endif

  sendStage(uid, "crushing", CRUSH_EXPECTED_MS);
  if (!crush()) {
    sendReject(uid, "mechanism", 0);
    return;
  }
  sendStage(uid, "draining", DRAIN_TIME_MS);
  drain();
  sendStage(uid, "dropping", DROP_EXPECTED_MS);
  if (!dropToScale()) {
    sendReject(uid, "mechanism", 0);
    return;
  }

  sendStage(uid, "weighing", WEIGH_EXPECTED_MS);
  int grams = readWeightGrams();
  if (grams == WEIGH_FAILED) {
    sendReject(uid, "mechanism", 0, scaleProblem);
  } else if (grams < MIN_ITEM_GRAMS) {
    sendReject(uid, "no_item", grams);
  } else if (grams > MAX_ITEM_GRAMS) {
    sendReject(uid, "too_heavy", grams);   // no points; the item still goes to the bin
  } else {
    sendWeight(uid, grams, pointsForGrams(grams));
  }

  sendStage(uid, "tipping", 0);
  tipIntoBin();
  sendBin(readBinLevel());
}

// ---------- Commands from the laptop ----------

#if !FAKE_SCALE
// Known weight on an already-zeroed scale -> counts per gram, saved in flash.
void calibrate(float knownGrams) {
  long counts = scale.read_average(20) - scale.get_offset();
  if (knownGrams <= 0 || labs(counts) < 1000) {
    Serial.println("# Calibration failed: tare with the scale empty, put the weight on, then cal <grams>");
    return;
  }
  gramsFactor = counts / knownGrams;
  Preferences settings;
  settings.begin("scale");   // same place firmware/scale_test saves it
  settings.putFloat("factor", gramsFactor);
  settings.end();
  Serial.printf("# Calibrated and saved: %.2f counts per gram.\n", gramsFactor);
}
#endif

void handleCommand(String line) {
  line.trim();
  if (line == "register") {
    registerMode = true;
    registerStarted = millis();
    Serial.println("# Register mode: tap a card to read it (no deposit).");
  } else if (line == "version") {
    sendBoot();   // the app asks after connecting, to see if a firmware update is due
  } else if (line == "cancel") {
    registerMode = false;
  } else if (line == "tare") {
#if !FAKE_SCALE
    scale.tare(20);
    Serial.println("# Scale zeroed.");
#endif
  } else if (line.startsWith("cal ")) {
#if !FAKE_SCALE
    calibrate(line.substring(4).toFloat());
#endif
  } else if (line.startsWith("rate ")) {
    int grams = line.substring(5).toInt();
    if (grams < 1 || grams > 1000) {
      Serial.println("# Rate must be 1 to 1000 grams per point.");
    } else {
      gramsPerPoint = grams;
      Preferences settings;
      settings.begin("points");
      settings.putInt("gpp", grams);
      settings.end();
      Serial.printf("# Points: 1 per %d g (saved).\n", grams);
    }
  } else if (line == "weigh") {
#if !FAKE_SCALE
    if (gramsFactor == 0) Serial.println("# Scale not calibrated: tare, put a known weight on, then cal <grams>");
    else Serial.printf("# Weight: %.1f g\n", readGramsOnce());
#endif
  } else if (line.length() > 0) {
    Serial.println("# Unknown command. Commands: register, cancel, tare, cal <grams>, weigh, rate <grams>, version");
  }
}

// ---------- Arduino entry points ----------

void setup() {
  Serial.begin(SERIAL_BAUD);
  Serial.setTimeout(100);
  pinMode(STATUS_LED_PIN, OUTPUT);
  delay(500);   // let the laptop's Serial Monitor catch up after a restart

  Preferences points;
  points.begin("points", true);
  gramsPerPoint = points.getInt("gpp", GRAMS_PER_POINT);
  points.end();

#if !FAKE_RFID
  SPI.begin();
  rfid.PCD_Init();
  byte version = rfid.PCD_ReadRegister(MFRC522::VersionReg);
  if (version == 0x00 || version == 0xFF) Serial.println("# RFID reader NOT answering. Check its wires.");
#endif

#if !FAKE_SCALE
  scale.begin(HX711_DT_PIN, HX711_SCK_PIN);
  Preferences settings;
  settings.begin("scale", true);   // same place firmware/scale_test saves it
  gramsFactor = settings.getFloat("factor", 0);
  settings.end();
  if (gramsFactor == 0) {
    Serial.println("# Scale NOT calibrated. Upload firmware/scale_test and calibrate first.");
  } else if (!scale.wait_ready_timeout(2000)) {
    Serial.println("# HX711 NOT answering. Check its wires.");
  } else {
    scale.tare(20);   // the tray must be empty at startup
  }
#endif

  sendBoot();
}

void loop() {
  if (Serial.available()) handleCommand(Serial.readStringUntil('\n'));
  if (registerMode && millis() - registerStarted > REGISTER_MODE_MS) registerMode = false;

#if !FAKE_RFID
  // The reader can reset itself after a power dip (e.g. a loose 3.3 V or RST
  // wire): it still answers but its antenna is off, so cards go unnoticed.
  // Check now and then and restart it. (Not on a timer regardless: restarting
  // the antenna would re-read a card left lying on the reader.)
  static unsigned long lastReaderCheck = 0;
  if (millis() - lastReaderCheck > RFID_CHECK_MS) {
    lastReaderCheck = millis();
    byte version = rfid.PCD_ReadRegister(MFRC522::VersionReg);
    bool antennaOn = (rfid.PCD_ReadRegister(MFRC522::TxControlReg) & 0x03) == 0x03;
    if (version == 0x00 || version == 0xFF || !antennaOn) {
      rfid.PCD_Init();
      Serial.println("# RFID reader had stopped; restarted it.");
    }
  }
#endif

  String uid = readCard();
  if (uid == "") return;

  if (registerMode) {
    registerMode = false;
    sendScan(uid);
    return;
  }

  sendCard(uid);
  digitalWrite(STATUS_LED_PIN, HIGH);
  runTransaction(uid);
  digitalWrite(STATUS_LED_PIN, LOW);
}
