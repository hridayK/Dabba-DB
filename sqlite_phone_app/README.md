# Android SQLite Remote Server

This Flutter application transforms an Android device into a standalone, remotely accessible SQLite Database Server. It listens for incoming WebSocket connections on the Local Area Network (LAN), enforces secure authentication, and executes remote SQL queries dynamically.

## Architecture Overview

The app is strictly modularized to separate the UI, the WebSocket engine, and the two distinct databases. If you are reading this to edit the code, here is where everything lives:

### 1. Database Layer (`lib/database/`)
There are **two entirely separate SQLite databases**:
* **`database_helper.dart` (`server_users.db`)**: This database is *strictly* for authentication. It stores usernames and SHA-256 hashed passwords. It manages the users who are allowed to connect to the server.
* **`data_db_helper.dart` (`app_data.db`)**: This is the dynamic, schema-less database. This is where remote client queries actually execute.

### 2. Server Layer (`lib/server/websocket_server.dart`)
This is the core engine. It relies on `dart:io` to bind an `HttpServer` to port `8080`.
* **Authentication Interceptor**: Before allowing a WebSocket upgrade, the server checks the `Authorization: Basic` header against `server_users.db`.
* **The `/db` Route**: The primary listener. It accepts JSON payloads containing SQL strings.
* **Concurrency & The Queue (`Lock`)**: Because Dart is single-threaded but database I/O is async, simultaneous write requests could cause race conditions. We use the `synchronized` package to instantiate a `Lock()`. Read queries (`query`) bypass the lock. Write queries (`execute` and `transaction`) wait in the lock's queue and execute sequentially.

### 3. User Interface (`lib/ui/`)
* **`home_screen.dart`**: The main dashboard. Starts/Stops the server, displays the IP address, and prints real-time server logs.
* **`users_screen.dart`**: A UI to securely add, edit, and delete authorized users. 
* **`settings_screen.dart`**: Modifies the global execution timeouts using `SharedPreferences`.

## Core Mechanisms to Note

* **Stateless Transactions**: To prevent database locks if a client drops their Wi-Fi connection mid-transaction, transactions are handled as a "Stateless Batch". The client sends an array of queries, and the server executes them all in a single atomic block. If one fails, `sqflite` rolls back the batch automatically.
* **Timeouts**: Every database operation is wrapped in a `Future.timeout()`. If an operation hangs (e.g. a bad SQL join), the Dart exception triggers an automatic SQLite `ROLLBACK`, releases the Queue lock, and prevents the server from hanging.

## API Documentation
For details on how a client should format their JSON payloads to send `query`, `execute`, or `transaction` requests, please read the [API Specifications](docs/api_spec.md).

## Running / Testing
1. Run the app on an emulator or physical device.
2. If using an Android emulator, you must forward the port to your PC:
   `adb forward tcp:8080 tcp:8080`
3. Connect via Postman or a WebSocket client using `ws://127.0.0.1:8080/db` with the `Authorization` header.
