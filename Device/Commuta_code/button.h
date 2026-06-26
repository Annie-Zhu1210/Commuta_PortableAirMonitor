// button.h - Single-button gesture detection for Commuta
//
// Polled state machine, called from the main loop. Detects:
//   * long-press (held for LONG_PRESS_MS or longer) - fires onLongPress
//     immediately at the threshold cross (so the caller can light a
//     confirmation LED while the user is still holding)
//   * double-press (two short clicks within DOUBLE_WINDOW_MS) - fires
//     onDoublePress on confirmation of the second press
//
// A single short press has no defined action and is silently discarded
// after DOUBLE_WINDOW_MS without a second click.
//
// Pin must be wired active-low; INPUT_PULLUP is configured internally.

#ifndef COMMUTA_BUTTON_H
#define COMMUTA_BUTTON_H

#include <stdint.h>

// Tunables. Exposed in the header so the wake-from-sleep validator in the
// main sketch can use the same long-press duration.
#define COMMUTA_BTN_DEBOUNCE_MS      20
#define COMMUTA_BTN_LONG_PRESS_MS    2000
#define COMMUTA_BTN_DOUBLE_WINDOW_MS 400

// Configure the pin and reset internal state. Call once in setup().
void commutaButtonBegin(int pin);

// Register callbacks. Pass nullptr to unregister. Either may be nullptr.
//
// onLongPressThreshold fires the moment the button has been held long
// enough; the user is still holding the button. Use this to light a
// "you can let go now" confirmation LED.
//
// onLongPress fires immediately after onLongPressThreshold. Separate hook
// so the shutdown handler can run distinct from the visual cue.
//
// onDoublePress fires when the second of two short clicks is confirmed
// (after debounce). The user may still be holding the second press.
void commutaButtonOnLongPressThreshold(void (*cb)());
void commutaButtonOnLongPress(void (*cb)());
void commutaButtonOnDoublePress(void (*cb)());

// Drive the state machine. Call once per main loop iteration.
void commutaButtonUpdate();

#endif  // COMMUTA_BUTTON_H