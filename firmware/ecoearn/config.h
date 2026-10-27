// EcoEarn firmware settings.
// Change values here instead of editing the main code.

#pragma once

#define FIRMWARE_VERSION "0.1.0"

// ---- Fake vs real hardware ----
// 1 = use a pretend value (hardware not connected yet)
// 0 = use the real sensor / motor
#define FAKE_RFID       1   // MFRC522 card reader
#define FAKE_SCALE      1   // load cell + HX711
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

// ---- Timing (milliseconds) ----
#define DRAIN_TIME_MS      5000   // wait after crushing so liquid drains out
#define FAKE_TAP_EVERY_MS 10000   // how often a pretend student taps a card

// ---- Pins ----
#define STATUS_LED_PIN 2     // built-in blue LED: on while a bottle is processed
