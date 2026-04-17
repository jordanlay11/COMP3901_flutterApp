## For gradle errors run:

flutter clean
flutter pub get

## Packages that might be needed:

flutter pub add flutter_blue_plus # BLE (did)
flutter pub add permission_handler (did)
flutter pub add flutter_ble_peripheral # advertising (did)
flutter pub add network_info_plus # IP info
flutter pub add wifi_iot # WiFi/hotspot control
flutter pub add connectivity_plus http

## Check if phone is connected

flutter devices

## Build APK, Install on phone, Launch app

flutter run

## reconnect device

flutter attach

## Replace in wifi service to upload online when me done(line 197)

Uri.parse("https://your-server.com/api/report")

---

## 📌 What should be working(needs testing)

BLE discovers nearby devices
Devices auto-connect over WiFi
Messages relay across devices (multi-hop mesh)
Works offline (stores + forwards messages)
Auto-uploads when internet is available

How to test
On Device A: Server → Advertise
On Device B: Server → Scan
Send message → should appear on both

Add Device C → test multi-hop
Turn off connections → send → reconnect → message delivers

Note
Devices must be on same WiFi for now
