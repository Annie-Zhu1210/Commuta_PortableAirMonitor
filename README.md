# Commuta — A Portable IoT Air Quality Monitor

**A wearable, battery-powered device that measures your personal air quality on the go — built to capture fine-particle (PM) exposure during everyday journeys on the London Underground.**

![Platform](https://img.shields.io/badge/hardware-ESP32-3C6EB4)
![App](https://img.shields.io/badge/app-Flutter%20(iOS)-02569B)
![Firmware](https://img.shields.io/badge/firmware-C%2B%2B%20/%20Arduino-00599C)
![Status](https://img.shields.io/badge/status-prototype-orange)


<p align="center">
  <img src="Media/Images/in_use1.jpg" alt="Commuta device" width="400">
</p>


---

## Overview

Commuta is a compact, self-contained air quality monitor designed to be carried through a daily commute. Most air quality data comes from fixed street-level stations, which say little about what a person actually breathes underground, on a platform, or inside a carriage. Commuta closes that gap: it logs particulate matter and supporting environmental readings continuously as you travel, then streams the data to a companion iOS app over Bluetooth Low Energy.

The result is a personal, location-aware record of exposure — the kind of data that lets you see, for example, how a deep, older Underground line compares to a sealed, modern one.


## Key Features

- **Personal PM monitoring** — measures PM1, PM2.5, PM4 and PM10 with a laser particle sensor.
- **Full environmental context** — also logs CO₂, temperature, humidity, VOC and NOx indices, and barometric pressure.
- **Fully portable** — runs off an onboard rechargeable LiPo battery, no wires or phone tether needed to collect data.
- **On-device logging** — data is buffered to flash storage, so nothing is lost if the phone is out of range.
- **BLE companion app** — a Flutter iOS app with a live air quality score, per-pollutant bands and health advice, maps, history charts, and CSV export ([full feature list](commuta_app#features)).
- **Discreet by design** — a custom 3D-printed enclosure and minimal indicator LEDs, intended to be worn unobtrusively.

## How It Works

Commuta is a three-part system: the **device** senses and logs, the **app** receives and tags, and the **analysis pipeline** turns raw logs into exposure insights.

<p align="center">
  <img src="Media/Images/system_flowchart .png" alt="System architecture" width="400">
</p>


## Hardware

The device is built around an ESP32 microcontroller with a stack of I²C sensors and a boosted power supply for the particle sensor.

| Component | Part | Role |
|---|---|---|
| Microcontroller | Adafruit HUZZAH32 (ESP32) | Sensing, logging, BLE |
| Particulate matter | Sensirion **SPS30** | PM1 / PM2.5 / PM4 / PM10 |
| CO₂ & climate | Sensirion **SCD40** | CO₂, temperature, humidity |
| Gas indices | Sensirion **SGP41** | VOC index, NOx index |
| Pressure | Infineon **DPS368** | Barometric pressure |
| Power | 2000 mAh LiPo + MT3608 boost | Portable supply (5 V for the SPS30) |

<p align="center">
  <img src="Media/Images/hardware.jpg" alt="Assembled hardware" width="450">
</p>

## Enclosure

A custom enclosure houses the electronics and battery in a wearable form factor. CAD and printable files live in [`/enclosure`](enclosure).

<p align="center">
  <img src="Media/Images/enclosure.png" alt="Enclosure" width="520">
</p>

## Repository Structure

| Folder | Contents |
|---|---|
| [`Device/`](Device) | `Commuta_code/`: main device firmware — sensor drivers, logging, and BLE communication (C++ / Arduino). `PCB/`: schematic and PCB gerber files. Plus the [Button & LED reference](Device/Button%26LED.md). |
| [`commuta_app/`](commuta_app) | The Flutter iOS companion app. **See its own [README](commuta_app) for features, architecture, and setup.** |
| [`enclosure/`](enclosure) | 3D-printable enclosure — see its [README](enclosure) for what to print and the design history. |
| [`data/`](data) | Field-study dataset: untouched raw device exports and a fully reproducible raw → clean pipeline — see its [README](data). |
| [`visualisation/`](visualisation) | Analysis scripts and figures for the Underground PM2.5 case study — see its [README](visualisation) for the script → figure map. |
| [`Battery/`](Battery) | LiPo battery discharge characterisation — data, script, and [report](Battery/battery_report.md). |
| [`test_SPS30/`](test_SPS30) | Standalone bring-up sketch for the SPS30 particle sensor. |
| [`test_PMS5003/`](test_PMS5003) | Early sensor evaluation sketch (PMS5003). |
| [`Media/`](Media) | Photos, diagrams, and figures. |

## Getting Started

### Device firmware
1. Open the sketch in [`Device/Commuta_code/`](Device/Commuta_code) with the Arduino IDE.
2. Install the ESP32 board package and the required Sensirion sensor libraries.
3. Copy `secrets_example.h` to `secrets.h` and generate your own BLE UUIDs (instructions inside the file). The same UUIDs go into the app's `ble_uuids.dart`.
4. Select the **Adafruit HUZZAH32 (ESP32)** board, connect over USB, and flash.

### Companion app
The iOS app is in [`commuta_app/`](commuta_app). Build and setup instructions are documented in that folder's README.

## Case Study: PM2.5 on the London Underground

As its first real-world deployment, Commuta was carried across six London Underground lines to study how line type and platform ventilation design affect commuters' PM2.5 exposure. The full chain is in this repo and is reproducible end to end:

1. **Collect** — the device logs readings during journeys; the app tags stations and exports CSVs.
2. **Clean** — [`data/`](data) holds the untouched raw exports and a rule-driven pipeline (`python data/process_data.py`) that regenerates the clean dataset from them.
3. **Analyse** — [`visualisation/`](visualisation) turns the clean data into the study's figures (`python visualisation/step0_dataprep.py`, then any figure script).

<p align="center">
  <img src="Media/Images/fig_perline_boxplot.png" alt="Platform PM2.5 exposure comparison across Underground lines" width="650">
</p>

## About the Project

Commuta was developed by Annie Zhu as a prototype on the **Connected Environments** programme at **UCL's Centre for Advanced Spatial Analysis (CASA)**; the Underground case study above formed the research component.

🔗 **Project site:** https://annie-zhu1210.github.io/commuta

## Acknowledgements

- Sensor integration benefited from technical guidance from Sensirion support.

---

<p align="center"><i>Built by Annie Zhu · UCL CASA</i></p>
