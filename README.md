## For gradle errors run:

flutter clean
flutter pub get

## Packages that might be needed:

flutter pub add flutter_blue_plus # BLE(did)
flutter pub add permission_handler(did)
flutter pub add flutter_ble_peripheral # advertising (did)
flutter pub add network_info_plus # IP info
flutter pub add wifi_iot # WiFi/hotspot control

## Check if phone is connected

flutter devices

## Build APK, Install on phone, Launch app

flutter run

## reconnect device

flutter attach
