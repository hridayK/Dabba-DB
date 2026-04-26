# SQLite Phone Client

A Python module to connect to the SQLite Phone App WebSocket server. It includes a connection pooling system with a minimum and maximum number of connections. It ensures individuals can query, execute, and perform transactions with minimum friction.

## Installation

You can install this directly from your GitHub repository using `pyproject.toml` or `pip`:

```bash
pip install "dabba-db-client @ git+https://github.com/hridayK/Dabba-DB.git#subdirectory=database-client-python"
```

Or in `pyproject.toml`:
```toml
dependencies = [
    "dabba-db-client @ git+https://github.com/hridayK/Dabba-DB.git#subdirectory=database-client-python"
]
```

## Usage

### Using the Pool (Minimum Friction)

The easiest way to interact with the database is via the `SQLitePool` which abstracts the connection management.

```python
import asyncio
from sqlite_phone_client import SQLitePool

async def main():
    # Initialize the pool with min 1 and max 5 connections
    pool = SQLitePool(
        host="192.168.1.100", 
        port=8080, 
        username="admin", 
        password="admin",
        min_size=2,
        max_size=10
    )
    await pool.initialize()

    # Query (bypasses lock)
    users = await pool.query("SELECT * FROM users WHERE status = ?", ["active"])
    print(users)

    # Execute (queued sequentially)
    inserted_id = await pool.execute("INSERT INTO users (name) VALUES (?)", ["Alice"])
    print(f"Inserted User ID: {inserted_id}")

    # Transaction (all-or-nothing batch)
    results = await pool.transaction([
        {"sql": "INSERT INTO logs (action) VALUES (?)", "args": ["Signup"]},
        {"sql": "UPDATE metrics SET signups = signups + 1"}
    ])
    print(f"Transaction Results: {results}")

    # Close pool when done
    await pool.close()

if __name__ == "__main__":
    asyncio.run(main())
```

### Acquiring a Connection

If you want to manage the connection state manually, you can acquire and release a connection from the pool.

```python
async def manual_connection(pool):
    conn = await pool.acquire()
    try:
        data = await conn.query("SELECT * FROM some_table")
        # do something else
    finally:
        await pool.release(conn)
```

## Features

- **Asynchronous**: Built on top of Python's `asyncio` and `websockets`.
- **Pooling**: `SQLitePool` manages the load with a minimum and maximum connection limit.
- **Easy Operations**: High-level wrapper methods `query`, `execute`, and `transaction` map directly to the underlying `api_spec.md` structure.
- **Connection Acquisition**: Exposes manual `acquire()` and `release()` options.
