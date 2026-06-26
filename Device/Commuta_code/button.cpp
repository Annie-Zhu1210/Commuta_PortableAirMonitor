// button.cpp - Polled button gesture detection.

#include "button.h"
#include <Arduino.h>

static int g_pin = -1;
static void (*g_onLongPressThreshold)() = nullptr;
static void (*g_onLongPress)() = nullptr;
static void (*g_onDoublePress)() = nullptr;

// State machine. The full lifecycle of a press is:
//   IDLE -> DEBOUNCING_DOWN -> HELD -> DEBOUNCING_UP -> IDLE
// with branches for long-press (fires from HELD) and double-press
// (fires when DEBOUNCING_DOWN confirms a second press within window).
enum class BtnState {
  IDLE,
  DEBOUNCING_DOWN,
  HELD,
  DEBOUNCING_UP,
};

static BtnState g_state = BtnState::IDLE;
static uint32_t g_stateMs = 0;          // when current state was entered
static uint32_t g_pressStartMs = 0;     // when the current press was confirmed
static bool g_longPressFired = false;   // long-press handler ran for this press
static bool g_suppressLongPress = false; // current press is the 2nd of a double; do not long-press
static bool g_firstClickPending = false;
static uint32_t g_firstClickReleasedMs = 0;

static bool isPressed() {
  // Active-low: GPIO reads LOW when the button is pressed.
  return digitalRead(g_pin) == LOW;
}

void commutaButtonBegin(int pin) {
  g_pin = pin;
  pinMode(g_pin, INPUT_PULLUP);
  g_state = BtnState::IDLE;
  g_stateMs = 0;
  g_pressStartMs = 0;
  g_longPressFired = false;
  g_suppressLongPress = false;
  g_firstClickPending = false;
  g_firstClickReleasedMs = 0;
}

void commutaButtonOnLongPressThreshold(void (*cb)()) { g_onLongPressThreshold = cb; }
void commutaButtonOnLongPress(void (*cb)())          { g_onLongPress = cb; }
void commutaButtonOnDoublePress(void (*cb)())        { g_onDoublePress = cb; }

void commutaButtonUpdate() {
  if (g_pin < 0) return;

  uint32_t now = millis();
  bool pressed = isPressed();

  switch (g_state) {
    case BtnState::IDLE:
      if (pressed) {
        g_state = BtnState::DEBOUNCING_DOWN;
        g_stateMs = now;
      } else if (g_firstClickPending &&
                 (now - g_firstClickReleasedMs) > COMMUTA_BTN_DOUBLE_WINDOW_MS) {
        // Single short click expired without a follow-up. No action defined
        // for a lone short press, so just clear the pending flag.
        g_firstClickPending = false;
      }
      break;

    case BtnState::DEBOUNCING_DOWN:
      if (!pressed) {
        // Bounced off without settling — treat as no press at all.
        g_state = BtnState::IDLE;
      } else if (now - g_stateMs >= COMMUTA_BTN_DEBOUNCE_MS) {
        // Press confirmed.
        g_pressStartMs = now;
        g_longPressFired = false;
        g_suppressLongPress = false;

        if (g_firstClickPending &&
            (now - g_firstClickReleasedMs) <= COMMUTA_BTN_DOUBLE_WINDOW_MS) {
          // This is the second press of a double. Fire now and suppress
          // long-press on this press (we don't want a held second click
          // to also trigger shutdown).
          g_firstClickPending = false;
          g_suppressLongPress = true;
          if (g_onDoublePress) g_onDoublePress();
        }
        g_state = BtnState::HELD;
      }
      break;

    case BtnState::HELD:
      if (!pressed) {
        g_state = BtnState::DEBOUNCING_UP;
        g_stateMs = now;
      } else if (!g_longPressFired && !g_suppressLongPress &&
                 (now - g_pressStartMs) >= COMMUTA_BTN_LONG_PRESS_MS) {
        // Threshold crossed. Light the confirmation LED first, then fire
        // the action. The user is still holding the button at this point;
        // the shutdown handler will wait for release before sleeping.
        g_longPressFired = true;
        if (g_onLongPressThreshold) g_onLongPressThreshold();
        if (g_onLongPress) g_onLongPress();
      }
      break;

    case BtnState::DEBOUNCING_UP:
      if (pressed) {
        // Bounced back to pressed; resume HELD without resetting the
        // press-start time so a marginal release doesn't reset the long-
        // press timer.
        g_state = BtnState::HELD;
      } else if (now - g_stateMs >= COMMUTA_BTN_DEBOUNCE_MS) {
        // Release confirmed.
        if (g_longPressFired) {
          // Long-press already handled; just clear any stale single-click.
          g_firstClickPending = false;
        } else if (g_suppressLongPress) {
          // This was the second press of a double-press; double-press
          // already fired on press-down. Nothing to do on release.
          g_suppressLongPress = false;
          g_firstClickPending = false;
        } else {
          // Short press completed. Could be the first click of a double.
          g_firstClickPending = true;
          g_firstClickReleasedMs = now;
        }
        g_state = BtnState::IDLE;
      }
      break;
  }
}