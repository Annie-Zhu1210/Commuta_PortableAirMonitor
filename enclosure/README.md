# Commuta Enclosure

3D-printable enclosure for the Commuta device — a compact, wearable case that houses the ESP32, sensor stack, boost converter, and 2000 mAh LiPo battery, with openings for airflow to the particle sensor, the USB-C charging port, and the single control button.

<p align="center">
  <img src="Media/Images/enclosure.png" alt="Commuta enclosure" width="520">
</p>

## What to print

Everything you need for a complete enclosure is in [`final_version/`](final_version):

| File | Part |
|---|---|
| `FinalVersion_Top.stl` | Top shell |
| `FinalVersion_Bottom.stl` | Bottom shell |
| `ButtonCover3.stl` | Button cap for the power/status button |
| `TypeC.stl` | USB-C port cover |
| `FinalVersion_浮雕.3mf` | Embossed (relief) logo variant of the shell — a multi-body 3MF for printing the raised Commuta wordmark, e.g. in a second colour |

The `.3mf` file preserves the separate relief bodies, so open it in your slicer directly (rather than converting to STL) if you want to assign the embossed text its own colour or material.

Printed in PLA with standard settings; no supports are required for the shells in their natural print orientation. The two shells close around the electronics, so check the fit of your assembled stack before committing to long prints.

## Design history

Folders `version1/` through `version9/` document the design's evolution and are kept for reference — none of them are needed to build the device:

- **version1–2** — first fit tests: single shell, then a split top/bottom design.
- **version3** — confirmed the approximate dimensions and necessary openings.
- **version4–5** — tested connection configurations using two sets and four sets of magnets, respectively.
- **version6** — refined shells plus the first embossed-logo (浮雕) experiments as separate relief bodies.
- **version7-10** — button cap and adaptor cover iterations; adjusted button and LED openings dimensions.

## Related

- [Hardware overview](../README.md#hardware) — what goes inside
- [Button & LED reference](../Device/Button%26LED.md) — how the single button and bi-colour LED work
