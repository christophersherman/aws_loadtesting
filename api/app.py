# api/main.py
import uuid
import hashlib
import sqlite3
import asyncio
from fastapi import FastAPI, Request
from contextlib import asynccontextmanager

def fibonacci(n: int) -> int:
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create a single in-memory SQLite connection with check_same_thread disabled,
    # so it can be shared across threads.
    conn = sqlite3.connect(':memory:', check_same_thread=False)
    c = conn.cursor()
    # Create the table only once.
    c.execute('''CREATE TABLE test (id TEXT, hash TEXT)''')
    conn.commit()
    # Store the connection in app.state for use in endpoints.
    app.state.db = conn
    yield
    conn.close()

# Create FastAPI with the lifespan context manager.
app = FastAPI(lifespan=lifespan)

async def mock_external_api_call():
    await asyncio.sleep(0.05)

def insert_db(conn, request_id: str, hash_digest: str):
    c = conn.cursor()
    c.execute("INSERT INTO test VALUES (?, ?)", (request_id, hash_digest))
    conn.commit()

@app.get("/test")
async def test_endpoint(request: Request):
    # Generate unique ID and compute its SHA256 hash.
    request_id = str(uuid.uuid4())
    hash_digest = hashlib.sha256(request_id.encode()).hexdigest()
    
    # CPU-bound operation.
    fib_result = fibonacci(20)
    
    # Insert into the DB using the pre-created connection.
    await asyncio.to_thread(insert_db, request.app.state.db, request_id, hash_digest)
    
    # Simulate an external API call.
    await mock_external_api_call()
    
    return {
        "status": "success",
        "request_id": request_id,
        "fib_result": fib_result
    }
