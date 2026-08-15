import re

# awg_manage substitutes the client name into sed/awk expressions and, over SSH,
# into a remote shell command. Keep it to characters that are inert in both.
NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,32}$")

MODES = ("split", "full")


class InvalidName(ValueError):
    pass


def check_name(name):
    if not NAME_RE.match(name or ""):
        raise InvalidName(
            "client name must be 1-32 chars of letters, digits, '-' or '_'"
        )
    return name


def list_clients(ex):
    out = ex.run(["--listclients"])
    return sorted(line.strip() for line in out.splitlines() if line.strip())


def add_client(ex, name, mode="split"):
    check_name(name)
    if mode not in MODES:
        raise ValueError(f"unknown mode: {mode}")
    ex.run(["--addclient", name, f"--{mode}"])


def remove_client(ex, name):
    check_name(name)
    ex.run(["--removeclient", name, "-y"])


def get_config(ex, name):
    check_name(name)
    return ex.run(["--showclientcfg", name])


def client_mode(config):
    for line in config.splitlines():
        if line.startswith("AllowedIPs"):
            return "full" if line.split("=", 1)[1].strip() == "0.0.0.0/0" else "split"
    return "unknown"
