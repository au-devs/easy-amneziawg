import os
import sqlite3
from contextlib import contextmanager

DB_PATH = os.environ.get("PANEL_DB", "/data/panel.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS servers (
  id         INTEGER PRIMARY KEY,
  name       TEXT NOT NULL UNIQUE,
  mode       TEXT NOT NULL CHECK (mode IN ('local','ssh')),
  ssh_host   TEXT,
  ssh_port   INTEGER NOT NULL DEFAULT 22,
  ssh_user   TEXT,
  container  TEXT NOT NULL DEFAULT 'amneziawg',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
"""


@contextmanager
def _conn():
    con = sqlite3.connect(DB_PATH, timeout=10)
    con.row_factory = sqlite3.Row
    try:
        yield con
        con.commit()
    finally:
        con.close()


def init():
    parent = os.path.dirname(DB_PATH)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with _conn() as con:
        con.executescript(SCHEMA)


def list_servers():
    with _conn() as con:
        return con.execute("SELECT * FROM servers ORDER BY name").fetchall()


def get_server(server_id):
    with _conn() as con:
        return con.execute("SELECT * FROM servers WHERE id = ?", (server_id,)).fetchone()


def add_server(name, mode, ssh_host, ssh_port, ssh_user, container):
    with _conn() as con:
        cur = con.execute(
            "INSERT INTO servers (name, mode, ssh_host, ssh_port, ssh_user, container)"
            " VALUES (?, ?, ?, ?, ?, ?)",
            (name, mode, ssh_host, ssh_port, ssh_user, container),
        )
        return cur.lastrowid


def delete_server(server_id):
    with _conn() as con:
        con.execute("DELETE FROM servers WHERE id = ?", (server_id,))
