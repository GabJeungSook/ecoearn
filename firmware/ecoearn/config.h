// EcoEarn firmware settings.
// Change values here instead of editing the main code.

#pragma once

#define FIRMWARE_VERSION "0.2.4"

// ---- Fake vs real hardware ----
// 1 = use a pretend value (hardware not connected yet)
// 0 = use the real sensor / motor
#define FAKE_RFID       0   // MFRC522 card reader
#define FAKE_SCALE      0   // load cell + HX711
#define FAKE_BIN_LEVEL  1   // ultrasonic sensor
#define FAKE_MECHANISM  1   // actuator, servos, IR sensor, lid switch

// ---- Serial link to the laptop ----
#define SERIAL_BAUD 115200

// ---- Points ----
// PLACEHOLDER until the group confirms the rate.
#define GRAMS_PER_POINT 10   // 1 point for every 10 g (decimals are dropped)

// ---- Item checks ----
#define MIN_ITEM_GRAMS 5     // lighter than this = nothing was deposited
#define MAX_ITEM_GRAMS 80    // heavier than this = rejected (not a drained bottle)

// ---- Storage bin ----
#define BIN_FULL_PERCENT 90  // refuse new bottles at or above this fill level

// ---- Scale ----
// Calibration: "cal <grams>" command (or firmware/scale_test), saved in the ESP32's flash.
// Measured noise on the test bench: about +/-2.5 g per 0.3 s reading.
#define SAMPLES_PER_READING 5     // HX711 conversions averaged per reading (0.5 s)
#define STABLE_GRAMS      3.0     // readings within this range count as settled (points are per 10 g)
#define STABLE_READINGS   4       // ...for this many readings in a row; weight = their average
#define WEIGH_TIMEOUT_MS  10000   // give up waiting for a settled reading

// ---- Timing (milliseconds) ----
#define DRAIN_TIME_MS      5000   // wait after crushing so liquid drains out
#define FAKE_TAP_EVERY_MS 10000   // how often a pretend student taps a card
#define REGISTER_MODE_MS  30000   // register mode ends if no card is tapped
#define REMOVE_ITEM_MS    30000   // fake mechanism: time to take the item off the scale

// ---- Pins ----
#define STATUS_LED_PIN 2     // built-in blue LED: on while a bottle is processed
#define RFID_SDA_PIN   5     // MFRC522 (SPI: SCK 18, MOSI 23, MISO 19)
#define RFID_RST_PIN   22
#define HX711_DT_PIN   16
#define HX711_SCK_PIN  17
