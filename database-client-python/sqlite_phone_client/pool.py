import asyncio
from typing import Optional, List
from .connection import SQLiteConnection

class SQLitePool:
    """
    A connection pool for SQLite Phone App WebSocket Server.
    Maintains a minimum number of connections and scales up to a maximum.
    """
    def __init__(self, host: str, port: int, username: str = None, password: str = None, min_size: int = 1, max_size: int = 5):
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.min_size = min_size
        self.max_size = max_size
        self._pool = asyncio.Queue(maxsize=max_size)
        self._current_size = 0
        self._lock = asyncio.Lock()

    async def initialize(self):
        """
        Initializes the pool by creating the minimum number of connections.
        """
        for _ in range(self.min_size):
            await self._create_connection()

    async def _create_connection(self):
        conn = SQLiteConnection(self.host, self.port, self.username, self.password)
        await conn.connect()
        await self._pool.put(conn)
        self._current_size += 1

    async def acquire(self) -> SQLiteConnection:
        """
        Acquires a connection from the pool.
        Creates a new connection if the pool is empty but below max_size.
        If at max_size, waits until a connection is available.
        """
        async with self._lock:
            if self._pool.empty() and self._current_size < self.max_size:
                await self._create_connection()
        
        return await self._pool.get()

    async def release(self, conn: SQLiteConnection):
        """
        Releases a connection back to the pool.
        """
        await self._pool.put(conn)

    async def close(self):
        """
        Closes all connections in the pool.
        """
        while not self._pool.empty():
            conn = await self._pool.get()
            await conn.close()
        self._current_size = 0

    # Minimum Friction Methods

    async def query(self, sql: str, args: list = None, timeout_seconds: int = None) -> list:
        """
        Executes a Read query (e.g., SELECT) securely fetching a connection.
        """
        conn = await self.acquire()
        try:
            return await conn.query(sql, args, timeout_seconds)
        finally:
            await self.release(conn)

    async def execute(self, sql: str, args: list = None, timeout_seconds: int = None) -> int:
        """
        Executes a Write query (e.g., INSERT, UPDATE, DELETE) securely fetching a connection.
        """
        conn = await self.acquire()
        try:
            return await conn.execute(sql, args, timeout_seconds)
        finally:
            await self.release(conn)

    async def transaction(self, operations: list, timeout_seconds: int = None) -> list:
        """
        Executes a stateless batch transaction securely fetching a connection.
        """
        conn = await self.acquire()
        try:
            return await conn.transaction(operations, timeout_seconds)
        finally:
            await self.release(conn)
