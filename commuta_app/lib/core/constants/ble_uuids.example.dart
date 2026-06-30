// BLE UUIDs — EXAMPLE / TEMPLATE FILE
//
// Copy this file to `ble_uuids.dart` in the same directory, then replace
// each placeholder UUID below with the matching value from the device
// firmware's `secrets.h`. The real file is gitignored; this example is
// committed so cloners know what structure to fill in.
//
// A mismatch on `service` will cause the scan to silently find nothing.
// A mismatch on a characteristic will cause GATT discovery to silently
// miss it. There are no runtime errors for wrong UUIDs.

/// BLE UUIDs for the Commuta device.
///
/// UUIDs are stored as bare strings so this file has no dependency on
/// `flutter_blue_plus`. `BLEManager` wraps each value in a `Guid` at
/// the use site.
class BleUuids {
  BleUuids._();

  /// Primary service exposing the three Commuta characteristics.
  static const String service =
      '00000000-0000-0000-0000-000000000000';

  /// Live characteristic — notifications of 40-byte `CommutaSample`
  /// packets at the device's 10 s sampling interval.
  static const String liveCharacteristic =
      '00000000-0000-0000-0000-000000000001';

  /// Status characteristic — notifications of 24-byte `CommutaStatus`
  /// packets carrying battery, buffered count, uptime, and flags.
  static const String statusCharacteristic =
      '00000000-0000-0000-0000-000000000002';

  /// Buffered characteristic — write a 9-byte request to start a
  /// catch-up sync; receive notifications of data and EOS frames.
  static const String bufferedCharacteristic =
      '00000000-0000-0000-0000-000000000003';
}