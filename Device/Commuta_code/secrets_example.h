// secrets_example.h - template for secrets.h
//
// This file IS committed to the repo. It documents the structure of
// secrets.h so anyone setting up the project knows what to fill in.
//
// To use:
//   1. Copy this file to "secrets.h" in the same directory.
//   2. Replace every "REPLACE-WITH-YOUR-OWN-..." value with your own.
//   3. Generate UUIDs with `uuidgen` (Linux/macOS) or https://www.uuidgenerator.net/.
//   4. secrets.h is gitignored, so your values stay local.

#ifndef COMMUTA_SECRETS_H
#define COMMUTA_SECRETS_H

// ---------- BLE identity ----------
#define COMMUTA_BLE_NAME_PREFIX "Commuta-"

// ---------- BLE GATT UUIDs ----------
// All four UUIDs must be 128-bit (long form). Generate fresh values,
// do not reuse the placeholders.
#define COMMUTA_SERVICE_UUID "REPLACE-WITH-YOUR-OWN-UUID-000000000000"
#define COMMUTA_CHAR_LIVE_UUID "REPLACE-WITH-YOUR-OWN-UUID-000000000001"
#define COMMUTA_CHAR_BUFFERED_UUID "REPLACE-WITH-YOUR-OWN-UUID-000000000002"
#define COMMUTA_CHAR_STATUS_UUID "REPLACE-WITH-YOUR-OWN-UUID-000000000003"

#endif  // COMMUTA_SECRETS_H