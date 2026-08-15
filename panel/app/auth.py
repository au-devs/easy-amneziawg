import os
import secrets

from fastapi import Request
from fastapi.responses import Response
from starlette.middleware.base import BaseHTTPMiddleware

PASSWORD = os.environ.get("PANEL_PASSWORD", "")
USERNAME = os.environ.get("PANEL_USERNAME", "admin")


class BasicAuthMiddleware(BaseHTTPMiddleware):
    """HTTP Basic auth, active only when PANEL_PASSWORD is set."""

    async def dispatch(self, request: Request, call_next):
        header = request.headers.get("authorization", "")
        if _authorized(header):
            return await call_next(request)
        return Response(
            status_code=401,
            headers={"WWW-Authenticate": 'Basic realm="awg-panel"'},
        )


def _authorized(header):
    import base64
    import binascii

    scheme, _, token = header.partition(" ")
    if scheme.lower() != "basic":
        return False
    try:
        user, _, password = base64.b64decode(token).decode().partition(":")
    except (binascii.Error, UnicodeDecodeError, ValueError):
        return False
    # Compare both halves unconditionally so a wrong username costs the same as
    # a wrong password.
    ok_user = secrets.compare_digest(user, USERNAME)
    ok_pass = secrets.compare_digest(password, PASSWORD)
    return ok_user and ok_pass


def install(app):
    if PASSWORD:
        app.add_middleware(BasicAuthMiddleware)
    return bool(PASSWORD)
