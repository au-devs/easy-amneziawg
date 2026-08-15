import os
import shlex
import subprocess
from dataclasses import dataclass

SSH_KEY = os.environ.get("SSH_KEY", "/data/ssh/id_ed25519")
KNOWN_HOSTS = os.environ.get("KNOWN_HOSTS", "/data/ssh/known_hosts")
TIMEOUT = int(os.environ.get("EXEC_TIMEOUT", "30"))


class ExecError(RuntimeError):
    pass


def _run(argv, timeout=TIMEOUT):
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise ExecError(f"timed out after {timeout}s")
    except FileNotFoundError as exc:
        raise ExecError(str(exc))
    if proc.returncode != 0:
        raise ExecError((proc.stderr or proc.stdout).strip() or f"exit status {proc.returncode}")
    return proc.stdout


@dataclass
class LocalExecutor:
    container: str

    def run(self, argv):
        return _run(["docker", "exec", self.container, "awg_manage", *argv])


@dataclass
class SSHExecutor:
    host: str
    port: int
    user: str
    container: str

    def run(self, argv):
        # ssh concatenates its arguments and hands them to a remote shell, so every
        # element has to survive one round of shell parsing on the far side.
        remote = " ".join(
            shlex.quote(a) for a in ("docker", "exec", self.container, "awg_manage", *argv)
        )
        return _run(
            [
                "ssh",
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=5",
                "-o", "StrictHostKeyChecking=yes",
                "-o", f"UserKnownHostsFile={KNOWN_HOSTS}",
                "-i", SSH_KEY,
                "-p", str(self.port),
                f"{self.user}@{self.host}",
                "--",
                remote,
            ]
        )


def for_server(row):
    if row["mode"] == "local":
        return LocalExecutor(container=row["container"])
    return SSHExecutor(
        host=row["ssh_host"],
        port=row["ssh_port"],
        user=row["ssh_user"],
        container=row["container"],
    )
