import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

import segno
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, PlainTextResponse, RedirectResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from . import auth, awg, store
from .executor import ExecError, for_server

BASE_DIR = Path(__file__).parent
log = logging.getLogger("panel")

@asynccontextmanager
async def lifespan(app: FastAPI):
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
    store.init()
    bind = os.environ.get("PANEL_BIND", "127.0.0.1")
    if AUTH_ENABLED:
        log.info("basic auth enabled")
    elif bind not in ("127.0.0.1", "localhost", "::1"):
        log.warning(
            "auth is OFF and PANEL_BIND=%s -- anyone who can reach this port gets "
            "root on every connected VPN server. Set PANEL_PASSWORD before exposing it.",
            bind,
        )
    else:
        log.info("auth is off; listening on %s only", bind)
    yield


app = FastAPI(docs_url=None, redoc_url=None, lifespan=lifespan)
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")
templates = Jinja2Templates(directory=BASE_DIR / "templates")

AUTH_ENABLED = auth.install(app)


def _server_or_404(server_id):
    row = store.get_server(server_id)
    if row is None:
        raise LookupError(f"no such server: {server_id}")
    return row


def _clients_view(request, row, error=None):
    clients, list_error = [], None
    try:
        clients = awg.list_clients(for_server(row))
    except ExecError as exc:
        list_error = str(exc)
    return templates.TemplateResponse(
        "clients.html",
        {
            "request": request,
            "server": row,
            "clients": clients,
            "error": error,
            "list_error": list_error,
        },
    )


@app.get("/", response_class=HTMLResponse)
def index(request: Request):
    return templates.TemplateResponse(
        "servers.html", {"request": request, "servers": store.list_servers()}
    )


@app.post("/servers")
def create_server(
    name: str = Form(...),
    mode: str = Form(...),
    ssh_host: str = Form(""),
    ssh_port: int = Form(22),
    ssh_user: str = Form("root"),
    container: str = Form("amneziawg"),
):
    if mode not in ("local", "ssh"):
        return RedirectResponse("/?error=bad+mode", status_code=303)
    if mode == "ssh" and not ssh_host.strip():
        return RedirectResponse("/?error=ssh+host+required", status_code=303)
    try:
        store.add_server(
            name=name.strip(),
            mode=mode,
            ssh_host=ssh_host.strip() or None,
            ssh_port=ssh_port,
            ssh_user=ssh_user.strip() or None,
            container=container.strip() or "amneziawg",
        )
    except Exception as exc:  # unique name, constraint violations
        return RedirectResponse(f"/?error={exc}", status_code=303)
    return RedirectResponse("/", status_code=303)


@app.post("/servers/{server_id}/delete")
def remove_server(server_id: int):
    store.delete_server(server_id)
    return RedirectResponse("/", status_code=303)


@app.post("/servers/{server_id}/check", response_class=HTMLResponse)
def check_server(server_id: int):
    row = _server_or_404(server_id)
    try:
        count = len(awg.list_clients(for_server(row)))
    except ExecError as exc:
        return HTMLResponse(f'<span class="bad">{exc}</span>')
    return HTMLResponse(f'<span class="ok">ok, {count} client(s)</span>')


@app.get("/servers/{server_id}", response_class=HTMLResponse)
def clients(request: Request, server_id: int, error: str = ""):
    return _clients_view(request, _server_or_404(server_id), error or None)


@app.post("/servers/{server_id}/clients")
def create_client(server_id: int, name: str = Form(...), mode: str = Form("split")):
    row = _server_or_404(server_id)
    try:
        awg.add_client(for_server(row), name.strip(), mode)
    except (awg.InvalidName, ValueError, ExecError) as exc:
        return RedirectResponse(f"/servers/{server_id}?error={exc}", status_code=303)
    return RedirectResponse(f"/servers/{server_id}", status_code=303)


@app.post("/servers/{server_id}/clients/{name}/delete")
def delete_client(server_id: int, name: str):
    row = _server_or_404(server_id)
    try:
        awg.remove_client(for_server(row), name)
    except (awg.InvalidName, ExecError) as exc:
        return RedirectResponse(f"/servers/{server_id}?error={exc}", status_code=303)
    return RedirectResponse(f"/servers/{server_id}", status_code=303)


@app.get("/servers/{server_id}/clients/{name}/config")
def client_config(server_id: int, name: str):
    row = _server_or_404(server_id)
    config = awg.get_config(for_server(row), name)
    return PlainTextResponse(
        config,
        headers={"Content-Disposition": f'attachment; filename="{name}.conf"'},
    )


@app.get("/servers/{server_id}/clients/{name}/qr")
def client_qr(server_id: int, name: str):
    row = _server_or_404(server_id)
    config = awg.get_config(for_server(row), name)
    buf = segno.make(config).png_data_uri(scale=6)
    return HTMLResponse(
        f'<div class="qr"><img src="{buf}" alt="QR for {name}">'
        f"<p>Scan with the AmneziaWG app. Config mode: "
        f"<b>{awg.client_mode(config)}</b></p></div>"
    )


@app.exception_handler(LookupError)
def lookup_error(request: Request, exc: LookupError):
    return Response(str(exc), status_code=404, media_type="text/plain")


@app.exception_handler(ExecError)
def exec_error(request: Request, exc: ExecError):
    return Response(str(exc), status_code=502, media_type="text/plain")
