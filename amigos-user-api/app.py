"""
Amigos user-info API.

Read-only FastAPI service exposing per-user subscription data from the
3x-ui panel database:

    GET /api/user/{username} -> {"username","expiry","up","down","total"}

Field semantics (matches the Amigos Android app):
    expiry : epoch milliseconds when the account expires (0 = lifetime)
    up     : uploaded bytes (sum over all inbounds for this email)
    down   : downloaded bytes (sum over all inbounds for this email)
    total  : traffic quota in bytes (0 = unlimited)

Username match is exact first, then case-insensitive fallback
(the panel treats emails case-sensitively, the app preserves case,
so be lenient here).

Run behind nginx (see nginx-snippet.conf) on 127.0.0.1:8899.
The x-ui database is opened read-only; nothing is ever written.
"""

import json
import sqlite3
import urllib.parse
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

XUI_DB = "/etc/x-ui/x-ui.db"
TABLE_INBOUNDS = "inbounds"
TABLE_TRAFFICS = "client_traffics"

app = FastAPI(title="Amigos user-info API", docs_url=None, redoc_url=None)


def open_db() -> sqlite3.Connection:
    con = sqlite3.connect(f"file:{urllib.parse.quote(XUI_DB)}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    return con


def table_exists(con: sqlite3.Connection, name: str) -> bool:
    cur = con.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)
    )
    return cur.fetchone() is not None


def find_client(con: sqlite3.Connection, username: str):
    """Return (client_dict, inbound_id) for the user, or (None, None)."""
    rows = con.execute(
        f"SELECT id, settings FROM {TABLE_INBOUNDS}"
    ).fetchall()
    fallback = (None, None)
    for row in rows:
        try:
            settings = json.loads(row["settings"] or "{}")
        except (json.JSONDecodeError, TypeError):
            continue
        clients = settings.get("clients")
        if not isinstance(clients, list):
            continue
        for client in clients:
            if not isinstance(client, dict):
                continue
            email = str(client.get("email") or "")
            if email == username:
                return client, row["id"]
            if fallback[0] is None and email.lower() == username.lower():
                fallback = (client, row["id"])
    return fallback


def sum_traffic(con: sqlite3.Connection, username: str) -> tuple[int, int]:
    """Return (up, down) bytes summed over all inbounds for this email."""
    if not table_exists(con, TABLE_TRAFFICS):
        return 0, 0
    cur = con.execute(
        f"SELECT COALESCE(SUM(up),0) AS up, COALESCE(SUM(down),0) AS down "
        f"FROM {TABLE_TRAFFICS} WHERE email=? OR LOWER(email)=LOWER(?)",
        (username, username),
    )
    row = cur.fetchone()
    return int(row["up"] or 0), int(row["down"] or 0)


def to_int(value, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


@app.get("/api/user/{username}")
def user_info(username: str):
    username = username.strip()
    if not username or len(username) > 64:
        raise HTTPException(status_code=400, detail="bad username")
    try:
        con = open_db()
    except sqlite3.Error:
        raise HTTPException(status_code=503, detail="database unavailable")
    try:
        client, _ = find_client(con, username)
        if client is None:
            raise HTTPException(status_code=404, detail="user not found")
        up, down = sum_traffic(con, str(client.get("email") or username))
        return JSONResponse(
            {
                "username": str(client.get("email") or username),
                "expiry": to_int(client.get("expiryTime"), 0),
                "up": up,
                "down": down,
                "total": to_int(client.get("total"), 0),
            }
        )
    finally:
        con.close()


@app.get("/api/health")
def health():
    return {"ok": True}
