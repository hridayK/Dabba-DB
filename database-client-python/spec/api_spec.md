# SQLite Phone App - API Specification

This document details how to connect to the SQLite WebSocket Server and the JSON payload specifications required to execute database operations remotely.

## 1. Connection & Authentication

The server runs via WebSockets and is protected by standard HTTP Basic Authentication.

* **Base URL**: `ws://<server_ip>:<port>`
* **Authentication**: You must pass an `Authorization` header with the HTTP Upgrade request. The value must be `Basic <base64_encoded_username:password>`.
  
  *Example Header*:
  `Authorization: Basic YWRtaW46YWRtaW4=` *(For `admin:admin`)*

## 2. Routes

The server exposes two distinct WebSocket routes:

### `/ws` (Echo/Chat Route)
* **URL**: `ws://<server_ip>:<port>/ws`
* **Description**: A simple test route. Any text message sent to this route will be echoed back by the server, prepended with your username.

### `/db` (Database Route)
* **URL**: `ws://<server_ip>:<port>/db`
* **Description**: The primary route for executing remote SQLite operations against the `app_data.db` database.
* **Format**: All messages sent to this route must be valid JSON strings following the specifications below.

---

## 3. The JSON Protocol (for `/db`)

All requests must include a `method` field dictating the type of operation. The server strictly distinguishes between reads, writes, and batch transactions to maintain database integrity and manage locking/queues.

### A. Read Queries (`method: "query"`)
Used for retrieving data (e.g., `SELECT`, `PRAGMA`). These queries bypass the queue lock and execute immediately and concurrently.

**Request payload:**
```json
{
  "method": "query",
  "sql": "SELECT * FROM my_table WHERE status = ?",
  "args": ["active"]
}
```
*   `sql` (String, required): The raw SQL query.
*   `args` (Array, optional): A list of positional arguments to bind to the `?` placeholders.

**Success Response:**
```json
{
  "status": "success",
  "data": [
    {"id": 1, "name": "Item A", "status": "active"}
  ]
}
```

### B. Write Queries (`method: "execute"`)
Used for operations that modify the database (e.g., `INSERT`, `UPDATE`, `DELETE`, `CREATE`, `DROP`). These queries are queued in a turnstile lock and execute strictly sequentially to prevent database corruption.

**Request payload:**
```json
{
  "method": "execute",
  "sql": "INSERT INTO my_table (name, status) VALUES (?, ?)",
  "args": ["Item B", "pending"]
}
```

**Success Response:**
```json
{
  "status": "success",
  "insertId_or_affectedRows": 2
}
```
*Note: Depending on the query type (`INSERT` vs `UPDATE`), the return value represents either the last inserted ID or the number of rows affected.*

### C. Stateless Batch Transactions (`method: "transaction"`)
Executes an array of queries in a single, atomic SQLite transaction. If any operation within the array fails, the entire transaction is automatically rolled back.

**Request payload:**
```json
{
  "method": "transaction",
  "timeout_seconds": 10,
  "operations": [
    {
      "sql": "INSERT INTO accounts (balance) VALUES (?)",
      "args": [100]
    },
    {
      "sql": "UPDATE logs SET activity = ?",
      "args": ["Account created"]
    }
  ]
}
```
*   `operations` (Array, required): A list of objects containing `sql` and optional `args`.

**Success Response:**
```json
{
  "status": "success",
  "results": [1, 1] 
}
```
*Note: The `results` array contains the integer output (insert ID or affected rows) corresponding to each operation in the exact order they were sent.*

---

## 4. Timeouts & Error Handling

To prevent runaway queries or massive unindexed table scans from locking the database indefinitely, all queries are protected by a strict execution timeout. 

### Setting Timeouts
You can override the server's default timeout (configured via the app's Settings UI) on a per-request basis by sending `timeout_seconds`:

```json
{
  "method": "query",
  "sql": "SELECT * FROM massive_table",
  "timeout_seconds": 15
}
```

### Error Responses
If a timeout occurs, a SQL syntax error is encountered, or the JSON payload is malformed, the server will return an error response:

```json
{
  "status": "error",
  "message": "Detailed error string provided by SQLite or the JSON parser"
}
```
