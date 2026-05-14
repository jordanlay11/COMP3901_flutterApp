## Project Description

This project is an offline-capable emergency response application built with Flutter and Dart that enables users to send SOS alerts and incident reports even when internet connectivity is unavailable during disasters such as hurricanes. The system uses a hybrid mesh networking architecture combining BLE for device discovery and WiFi Direct for peer-to-peer data transfer, allowing nearby devices to relay emergency messages through the network until connectivity is restored. The application supports offline queueing, automatic synchronization, GPS location integration, authentication, and backend communication through Flask APIs, providing a resilient platform for emergency communication in low-connectivity environments.

## Setup instructions

You will need android studios and flutter installed and configured/added to path on your laptop
Connect laptop to android phone using USB(enable usb debugging on device in developer mode)
Give laptop permission to do usb debugging on phone when prompted(immediately after connecting USB)
In your terminal run:
flutter clean
flutter pub get
flutter run
These commands should install app on your phone.

In a seperate terminal:(you will need to install python and add it to path)
cd flask-backend
python -m venv venv
.\venv\Scripts\activate
pip install -r requirements.txt
python app.py
These command should start backend server on your device.

You will need postgresql install and configures on your device.
The database schema is in /flask-backend.
Create the database and create the tables using the schema.
Rename .env.sameple to .env in /flask-backend
Them fill out the .env file with your database credentials and a JWT secret.
