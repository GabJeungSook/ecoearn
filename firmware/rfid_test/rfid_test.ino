// EcoEarn - RFID reader test
//
// Checks that the MFRC522 reader answers, then prints the UID of every card
// held over it. Wiring (ESP32 30-pin board):
//   SDA -> D5   SCK -> D18   MOSI -> D23   MISO -> D19
//   RST -> D22  GND -> GND   3.3V -> 3V3   IRQ -> not connected

#include <SPI.h>
#include <MFRC522.h>

const int RFID_SDA_PIN = 5;
const int RFID_RST_PIN = 22;

MFRC522 rfid(RFID_SDA_PIN, RFID_RST_PIN);

bool readerWasOk = false;
unsigned long lastCheck = 0;

// The reader's chip version: 0x91 or 0x92 on genuine chips; clones report other
// values but usually still work. 0x00 or 0xFF means nothing is answering.
bool readerAnswers() {
  byte version = rfid.PCD_ReadRegister(MFRC522::VersionReg);
  return version != 0x00 && version != 0xFF;
}

void setup() {
  Serial.begin(115200);
  delay(500);
  SPI.begin();
  rfid.PCD_Init();

  byte version = rfid.PCD_ReadRegister(MFRC522::VersionReg);
  Serial.printf("\nReader chip version: 0x%02X\n", version);
  readerWasOk = readerAnswers();
  Serial.println(readerWasOk ? "Reader found. Hold a card over it..."
                             : "NO reader found. Check the wires and press the reader onto its pins.");
}

void loop() {
  // Every 2 seconds, report if the reader stops or starts answering
  // (useful while the pins are only pressed in, not soldered).
  if (millis() - lastCheck > 2000) {
    lastCheck = millis();
    bool ok = readerAnswers();
    if (ok != readerWasOk) {
      if (ok) rfid.PCD_Init();
      Serial.println(ok ? "Reader is answering again." : "Reader stopped answering (loose contact?).");
      readerWasOk = ok;
    }
  }

  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) return;

  Serial.print("Card UID: ");
  for (byte i = 0; i < rfid.uid.size; i++) {
    Serial.printf("%02X", rfid.uid.uidByte[i]);
  }
  Serial.println();
  rfid.PICC_HaltA(); // wait for the card to be taken away and tapped again
}
