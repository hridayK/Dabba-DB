import json
import base64
import websockets

class SQLiteConnection:
    """
    Handles a single WebSocket connection to the SQLite Server.
    """
    def __init__(self, host: str, port: int, username: str = None, password: str = None):
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.ws = None

    async def connect(self):
        url = f"ws://{self.host}:{self.port}/db"
        headers = {}
        if self.username and self.password:
            creds = f"{self.username}:{self.password}"
            encoded = base64.b64encode(creds.encode()).decode()
            headers["Authorization"] = f"Basic {encoded}"
            
        self.ws = await websockets.connect(url, extra_headers=headers)

    async def close(self):
        if self.ws:
            await self.ws.close()
            self.ws = None

    async def _send_and_receive(self, payload: dict) -> dict:
        if not self.ws:
            raise RuntimeError("Not connected. Call connect() first.")
        
        await self.ws.send(json.dumps(payload))
        response = await self.ws.recv()
        data = json.loads(response)
        
        if data.get("status") == "error":
            raise Exception(f"Server Error: {data.get('message')}")
        return data

    async def query(self, sql: str, args: list = None, timeout_seconds: int = None) -> list:
        """
        Executes a Read query (e.g., SELECT).
        Bypasses the turnstile lock and executes concurrently.
        """
        payload = {"method": "query", "sql": sql}
        if args is not None:
            payload["args"] = args
        if timeout_seconds is not None:
            payload["timeout_seconds"] = timeout_seconds
            
        data = await self._send_and_receive(payload)
        return data.get("data", [])

    async def execute(self, sql: str, args: list = None, timeout_seconds: int = None) -> int:
        """
        Executes a Write query (e.g., INSERT, UPDATE, DELETE).
        Queued sequentially on the server.
        Returns the insert ID or number of affected rows.
        """
        payload = {"method": "execute", "sql": sql}
        if args is not None:
            payload["args"] = args
        if timeout_seconds is not None:
            payload["timeout_seconds"] = timeout_seconds
            
        data = await self._send_and_receive(payload)
        return data.get("insertId_or_affectedRows", 0)

    async def transaction(self, operations: list, timeout_seconds: int = None) -> list:
        """
        Executes a stateless batch transaction.
        Operations should be a list of dictionaries, e.g.:
        [{"sql": "INSERT INTO table (val) VALUES (?)", "args": [1]}]
        Returns a list of insert IDs or affected rows for each operation.
        """
        payload = {"method": "transaction", "operations": operations}
        if timeout_seconds is not None:
            payload["timeout_seconds"] = timeout_seconds
            
        data = await self._send_and_receive(payload)
        return data.get("results", [])
