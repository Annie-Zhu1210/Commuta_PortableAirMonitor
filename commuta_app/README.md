# commuta_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Setup

1. Copy `.env.example` to `.env` and fill in your API keys:
   - `TFL_API_KEY` from https://api-portal.tfl.gov.uk/
   - `OPENWEATHER_API_KEY` from https://openweathermap.org/api

2. Copy `android/secrets.properties.example` to `android/secrets.properties` 
   and fill in your Google Maps Android API key.

3. Copy `ios/Flutter/Secrets.xcconfig.example` to `ios/Flutter/Secrets.xcconfig` 
   and fill in your Google Maps iOS API key.

4. Run `flutter pub get` and you're ready to build.
