// EcoEarn - ESP32 firmware
//
// One transaction: card tap -> crush + drain -> weigh -> points -> into bin.
// Every message to the laptop is one JSON object on its own line.
// Hardware that isn't connected yet is faked (see the FAKE_ switches in config.h).

#include "config.h"

// Pretend student cards, used while FAKE_RFID is 1.
const char* FAKE_UIDS[] = { "A3F29B11", "5C7E0D42", "91B4E6F3" };
const int FAKE_UID_COUNT = sizeof(FAKE_UIDS) / sizeof(FAKE_UIDS[0]);

unsigned long lastFakeTap = 0;   // used while FAKE_RFID is 1
int fakeBinLevel = 10;           // percent, used while FAKE_BIN_LEVEL is 1

// ---------- Messages to the laptop ----------

void sendBoot() {
  Serial.printf("{\"event\":\"boot\",\"version\":\"%s\"}\n", FIRMWARE_VERSION);
}

void sendCard(const String& uid) {
  Serial.printf("{\"event\":\"card\",\"uid\":\"%s\"}\n", uid.c_str());
}

void sendWeight(const String& uid, int grams, int points) {
  Serial.printf("{\"event\":\"weight\",\"uid\":\"%s\",\"grams\":%d,\"points\":%d}\n",
                uid.c_str(), grams, points);
}

// reason: "bin_full", "mechanism", "no_item" or "too_heavy"
void sendReject(const String& uid, const char* reason, int grams) {
  Serial.printf("{\"event\":\"reject\",\"uid\":\"%s\",\"reason\":\"%s\",\"grams\":%d}\n",
                uid.c_str(), reason, grams);
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
  #error "Real RFID reader is not written yet. Set FAKE_RFID to 1 in config.h."
#endif
}

// Mechanism steps 2-5: bottle detected, lid closed, crush, drain, trapdoor opens.
// Returns false if something went wrong (lid opened, motion timed out).
bool crushAndDrain() {
#if FAKE_MECHANISM
  delay(1500);            // pretend: actuator extends and retracts
  delay(DRAIN_TIME_MS);   // liquid drains (same wait the real machine uses)
  delay(500);             // pretend: trapdoor drops bottle onto the scale
  return true;
#else
  #error "Real mechanism is not written yet. Set FAKE_MECHANISM to 1 in config.h."
#endif
}

// Mechanism step 6: stable weight of the crushed bottle, in grams.
int readWeightGrams() {
#if FAKE_SCALE
  if (random(8) == 0) return random(90, 150);   // now and then, a too-heavy item
  return random(12, 45);                        // typical crushed bottle
#else
  #error "Real scale is not written yet. Set FAKE_SCALE to 1 in config.h."
#endif
}

// Mechanism step 8: tray tilts the bottle into the storage bin, scale re-zeroes.
void tipIntoBin() {
#if FAKE_MECHANISM
  delay(500);
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
  return grams / GRAMS_PER_POINT;
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

  if (!crushAndDrain()) {
    sendReject(uid, "mechanism", 0);
    return;
  }

  int grams = readWeightGrams();
  if (grams < MIN_ITEM_GRAMS) {
    sendReject(uid, "no_item", grams);
  } else if (grams > MAX_ITEM_GRAMS) {
    sendReject(uid, "too_heavy", grams);   // no points; the item still goes to the bin
  } else {
    sendWeight(uid, grams, pointsForGrams(grams));
  }

  tipIntoBin();
  sendBin(readBinLevel());
}

// ---------- Arduino entry points ----------

void setup() {
  Serial.begin(SERIAL_BAUD);
  pinMode(STATUS_LED_PIN, OUTPUT);
  delay(500);   // let the laptop's Serial Monitor catch up after a restart
  sendBoot();
}

void loop() {
  String uid = readCard();
  if (uid == "") return;

  sendCard(uid);
  digitalWrite(STATUS_LED_PIN, HIGH);
  runTransaction(uid);
  digitalWrite(STATUS_LED_PIN, LOW);
}
