# Commuta — Button & LED Reference

Commuta has one button and one bi-colour LED (red, green, and yellow by combining the two). All interaction is through this single button.

## Turning the device on

Press and hold the button. After about 2 seconds, the **red LED turns on**. Release the button.

The red LED stays on while sensors warm up (about 30 seconds). When the device is ready to record, the LED briefly turns **green**, then goes dark. The device is now running normally; the LED stays off during operation so it doesn't draw attention on the Underground.

## Checking the device is alive

Double-press the button (two quick taps). The LED flashes twice:

- **Two green flashes** — running normally, all sensors responding
- **Two yellow flashes** — running, but one or more sensors aren't responding (check connections)
- **No flash at all** — the device is off; long-press to turn it on

## Turning the device off

Press and hold the button. After about 2 seconds, the **red LED turns on**. Keep holding or release , the device begins its shutdown:

- If the phone is connected and a data sync is in progress, the device finishes its current data frame before shutting down
- A final status notification is sent to the phone so the app knows how many samples remain unsynced
- The red LED stays on until shutdown is complete
- The LED goes dark and the device enters deep sleep

## LED quick reference

| What you see | What it means |
|---|---|
| Red, solid | Boot in progress, *or* shutdown in progress |
| Green, brief | Boot complete, device is now recording |
| Dark | Normal running operation (device on), or device is off |
| Two green flashes | Health check: all sensors OK |
| Two yellow flashes | Health check: one or more sensors not responding |

## Button quick reference

| Gesture | When device is **off** | When device is **on** |
|---|---|---|
| Single short press | (no effect — device stays asleep) | (no defined action) |
| Double press | (no effect) | Health-check flash |
| Long-press (~2 s) | Turn device on | Turn device off |