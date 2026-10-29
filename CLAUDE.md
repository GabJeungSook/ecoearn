# EcoEarn — Plastic Waste Disposal Management System

Grade 12 STEM research project (client group). I (developer) build the **system only**:
ESP32 firmware + offline Windows laptop app + algorithm documentation.
The group owns all hardware: buying, soldering, enclosure, mechanism.

I am a software developer (Flutter, Laravel), new to embedded/ESP32 work.
Explain hardware steps plainly, one step at a time.

## What the system does
Student taps RFID card → deposits plastic bottle → bottle is pierced/crushed and
drained → crushed bottle is weighed → points computed from weight → transaction saved.
Points can be deducted from approved school fines. Monthly reports required.

Research objectives the system must satisfy:
1. Algorithms for registration/authentication, compaction, weighing, point allocation
   (flowcharts + pseudocode are a deliverable).
2. Monthly report of transactions and points.
3. Evaluation of accuracy, reliability, usability — system should log test data and
   export CSV for their Chapter IV.

## Panel decisions (fixed)
- **Offline.** No internet/cloud. Data saved to an SD card on the ESP32.
- **Compact before weighing**, so leftover liquid is removed before weighing.

## Architecture (decided)
- **ESP32 firmware** (Arduino framework, C++): the controller, no screen.
  Reads sensors, drives motors, logs to SD card, timestamps from RTC,
  short text on a 20x4 I2C LCD, sends events to the laptop over USB serial.
- **Laptop app** (Flutter for Windows + SQLite + serial port package):
  used during testing. Live screen, student registration (assign RFID UID),
  import SD data, points ledger, fine deductions, monthly report export,
  test-data export.
- ESP32 must work standalone without the laptop (SD log + LCD). Laptop is optional.
- Firmware should be configurable (feature flags) so hardware changes = setting change.

### Serial protocol (ESP32 → laptop): one JSON object per line, 115200 baud
```
{"event":"boot","version":"0.1.0"}
{"event":"card","uid":"A3F29B11"}
{"event":"weight","uid":"A3F29B11","grams":18,"points":2}
{"event":"reject","uid":"A3F29B11","reason":"too_heavy","grams":120}
{"event":"bin","level":64}
```
Reject reasons: `bin_full`, `mechanism`, `no_item`, `too_heavy` (no points awarded).
The laptop must ignore any line that isn't valid JSON (the ESP32 prints its own
startup text after every reset).
Laptop → ESP32 commands are also one line each (e.g. calibration). Not finalized.

## Mechanism (crush → drain → weigh)
1. RFID tap
2. Bottle in chamber; IR sensor detects it; lid switch confirms closed
3. Linear actuator extends; spikes pierce + plate crushes
4. Retract, ~5 s drain (liquid exits via wall drain hole to hose/container, away from scale)
5. Trapdoor servo drops bottle onto weighing tray
6. Stable weight reading → points
7. Per-item max weight check (reject/flag if too heavy)
8. Tray servo tilts bottle into storage bin; scale re-zeroes
9. Ultrasonic checks bin fill level

Safety: nothing moves with lid open; timeout on every motion; manual switch goes to an
ESP32 input (never directly to the relay).

## Hardware status
In hand (confirmed from photos 2026-10-27): ESP32 (Type-C, 30-pin, CH340 USB chip),
MFRC522 RFID reader (HW-126) + white card + blue key-fob tag, 5 kg bar load cell + HX711,
830-point breadboard, 20 cm jumper wires, Arduino Uno clone (NOT used).
NOT in hand: microSD card module, DS3231 RTC (both needed for the offline SD log).

Needs soldering by the group before use:
- MFRC522 8-pin header (SDA, SCK, MOSI, MISO, IRQ, GND, RST, 3.3V)
- HX711 4-pin header (GND, DT, SCK, VCC)
- Load cell → HX711: red E+, black E−, white A−, green A+
  (swap white/green if readings come out negative)

Hardware issues flagged to the group (software can't fix):
- ESP32 cannot drive the HDMI monitor in their plan → laptop (testing) + 20x4 LCD.
- 12 V must never go directly into the ESP32 → buck converter to 5 V.
- Single-channel relay cannot retract the actuator → 2-channel relay H-bridge or BTS7960.
- Needed additions: DS3231 RTC, 20x4 I2C LCD, 2x MG996R servos, E18-D80NK IR sensor,
  lid limit switch, buck converters, voltage divider for HC-SR04 echo (5 V → 3.3 V).

Wiring rules: RFID reader on 3.3 V only (never 5 V). Unplug USB before rewiring.
Use the breadboard +/− rails to share the ESP32's 3.3 V and GND.

## Information still needed from the group
- Student list (name, ID number, grade/section)
- Points rate (e.g. 1 point per 10 g)
- Which fines are eligible and the points-to-peso rate
- Relay module: 1- or 2-channel?
- Linear actuator stroke (mm) and force (N)
- How the enclosure is built and by whom

## Progress / next steps
1. [x] Install Arduino IDE 2 + ESP32 board package
       (boards URL: https://espressif.github.io/arduino-esp32/package_esp32_index.json)
       Installed: Arduino IDE 2.3.10, esp32 by Espressif 3.3.12.
2. [x] Blink test on ESP32 (GPIO 2 LED), confirm Serial Monitor at 115200
       Board: "ESP32 Dev Module" on COM3, USB chip is CH340 (driver CH341SER installed).
       Board does NOT auto-enter download mode: hold BOOT when "Connecting..." appears
       (or hold BOOT, tap EN, release BOOT, then upload). Press EN after upload if needed.
       Optional permanent fix for the group: 10 µF capacitor between EN and GND.
3. [x] Fake-event firmware: ESP32 sends simulated card/weight/bin events over serial
       firmware/ecoearn/ (config.h = settings + FAKE_ switches). Tested on the board.
       Compile from CLI: "C:\Program Files\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe"
       compile --fqbn esp32:esp32:esp32 firmware/ecoearn
4. [x] Flutter Windows app: connect to COM port, parse JSON lines, display events
       app/ (Flutter 3.41.9 via FVM, see app/.fvmrc; flutter_libserialport).
       lib/serial/ = protocol parser + port connection, lib/live/ = live screen.
       Tested live against the ESP32 on COM3. Close Arduino Serial Monitor first:
       only one program can hold COM3. No SQLite/database yet.
       Run: cd app; fvm flutter run -d windows
4b. [x] SQLite database + student registration (app/lib/data, app/lib/students)
       DB: %APPDATA%\com.ecoearn\ecoearn_app\ecoearn.db (sqflite_common_ffi; sqlite3
       bundled by the sqlite3 package's build hook). Tables: students, deposits
       (one row per processed bottle, accepted or rejected; source 'live' or 'sd').
       Balance = SUM(deposits.points) per student; fine deductions not built yet.
       Rules: unassigned-card deposits are credited when that card is assigned;
       students with deposit history can't be deleted (remove their card instead).
       Students screen can read a card UID by tapping it on the reader ("Scan card").
       Known gaps for later:
       - Real firmware: a card tap starts a transaction, so scanning for registration
         needs a laptop→ESP32 "register mode" command.
       - SD import will duplicate live deposits unless the ESP32 sends a persistent
         transaction id (add with SD/RTC work).
4c. [x] Reports screen (app/lib/reports): monthly per-student totals + CSV exports
       (monthly report, month's deposits, all deposits = Chapter IV test data).
       CSV is UTF-8 with BOM so Excel shows ñ correctly.
4d. [x] Login + roles (app/lib/auth, app/lib/shell), DB schema v2 adds `accounts`
       (PBKDF2-SHA256 hashes). First run = create admin. Window opens maximized; F11.
       - admin: Live, Students, Reports, Accounts; exports officer data file
       - display: kiosk fullscreen Live, auto-connects to the ESP32, close/Alt+F4
         blocked, exit needs an admin password
       - officer: view only (Reports + read-only Students) of an imported .ecoearn
         file = SQLite copy with `accounts` dropped + `export_info`. Stored separately
         as officer_data.ecoearn, never mixed into the machine's DB.
       Group decision: no SD module, so officers get data via laptop export file.
       Serial + deposit recording run regardless of who is signed in.
       Not yet tested by hand. Earlier test data ("test" student) disappeared from
       ecoearn.db for an unknown reason; persistence verified in a test, re-check by hand.
4e. [ ] Fine deductions (needs eligible fines + points-to-peso rate from the group)
5. [ ] After soldering: wire + test MFRC522, then HX711 (calibrate with known weights)
       MFRC522 wiring (ESP32 left column, USB up): SDA→D5, SCK→D18, MOSI→D23,
       MISO→D19, RST→D22, GND→GND, 3.3V→3V3, IRQ unused. Test sketch:
       firmware/rfid_test (needs library MFRC522@1.4.12, installed).
       RFID WORKS after soldering (2026-10-29): chip version 0x92, UIDs 47A87362 and
       79EEB9A2 (white card / blue fob, which is which not recorded).
       Note: RST on GPIO 22 = default I2C SCL; move RST when the LCD/RTC (I2C) arrive.
       HX711 wiring: GND→GND, DT→RX2 (GPIO 16), SCK→TX2 (GPIO 17), VCC→3V3 (shared
       with the RFID via breadboard row 17; GND via row 15). Test + calibration sketch:
       firmware/scale_test (library "HX711 Arduino Library"@0.7.5, installed); serial
       commands t = zero, c <grams> = calibrate; factor saved in ESP32 flash (Preferences).
       5 kg load cell: expect ~±1 g after averaging/calibration; fine for 1 pt / 10 g.
6. [ ] Replace fake events with real sensor readings
7. [ ] SD logging + RTC, LCD, then mechanism (actuator, servos, IR, lid switch)
