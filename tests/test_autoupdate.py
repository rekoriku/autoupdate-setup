import os
import shutil
import subprocess
from pathlib import Path

SCRIPT_SRC = Path(__file__).resolve().parent.parent / "autoupdate.sh"


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content)
    path.chmod(0o755)


def _make_stubs(stub_dir: Path, calls_log: Path) -> None:
    env_log = f'{calls_log}'

    _write_executable(
        stub_dir / "apt",
        "#!/bin/sh\nexit 0\n",
    )

    _write_executable(
        stub_dir / "apt-get",
        f"""#!/bin/sh
printf 'apt-get %s\\n' "$*" >> "{env_log}"
exit 0
""",
    )

    _write_executable(
        stub_dir / "apt-cache",
        f"""#!/bin/sh
printf 'apt-cache %s\\n' "$*" >> "{env_log}"
printf 'Candidate: 1.0\\n'
exit 0
""",
    )

    _write_executable(
        stub_dir / "dpkg",
        f"""#!/bin/sh
printf 'dpkg %s\\n' "$*" >> "{env_log}"
# Simulate package not installed
exit 1
""",
    )

    _write_executable(
        stub_dir / "visudo",
        "#!/bin/sh\nexit 0\n",
    )

    _write_executable(
        stub_dir / "stat",
        f"""#!/bin/sh
# Minimal stat stub that satisfies autoupdate.sh checks
if [ "$1" = "-c" ]; then
    if [ "$2" = "%u" ]; then
        echo 0
        exit 0
    fi
    if [ "$2" = "%a" ]; then
        echo 700
        exit 0
    fi
fi
printf 'stat %s\\n' "$*" >> "{env_log}"
exit 0
""",
    )

    _write_executable(
        stub_dir / "id",
        "#!/bin/sh\nif [ \"$1\" = \"-u\" ]; then echo 0; exit 0; fi\n/usr/bin/id \"$@\"\n",
    )

    _write_executable(
        stub_dir / "install",
        f"""#!/bin/sh
mode=644
while getopts "o:g:m:" opt; do
    case "$opt" in
        m) mode=$OPTARG ;;
    esac
done
shift $((OPTIND - 1))
src="$1"
dst="$2"
mkdir -p "$(dirname "$dst")" || exit 1
cp "$src" "$dst" && chmod "$mode" "$dst"
printf 'install %s %s\\n' "$src" "$dst" >> "{env_log}"
""",
    )

    _write_executable(
        stub_dir / "unattended-upgrade",
        f"""#!/bin/sh
printf 'unattended-upgrade %s\\n' "$*" >> "{env_log}"
echo "dry-run ok"
exit 0
""",
    )


def test_autoupdate_runs_with_stubs(tmp_path: Path) -> None:
    stub_dir = tmp_path / "stubs"
    stub_dir.mkdir()
    calls_log = tmp_path / "calls.log"
    calls_log.touch()

    _make_stubs(stub_dir, calls_log)

    script_copy_dir = tmp_path / "path with space"
    script_copy_dir.mkdir()
    script_path = script_copy_dir / "autoupdate.sh"
    shutil.copy(SCRIPT_SRC, script_path)
    script_path.chmod(0o755)

    apt_conf_dir = tmp_path / "aptconf"
    apt_conf_dir.mkdir()
    sudoers_path = tmp_path / "sudoers" / "autoupdate"
    sudoers_path.parent.mkdir(parents=True)

    env = os.environ.copy()
    env.update(
        {
            # Use stubbed commands inside the script (script honors PATH_OVERRIDE)
            "PATH_OVERRIDE": f"{stub_dir}{os.pathsep}/usr/sbin:/usr/bin:/sbin:/bin",
            # Skip root check for the test harness
            "SKIP_ROOT_CHECK": "true",
            "LOG_DIR": str(tmp_path / "logs"),
            "APT_CONF_DIR": str(apt_conf_dir),
            "SUDOERS_TARGET": str(sudoers_path),
            "TARGET_USER": "tester",
            "ENABLE_NOPASSWD": "true",
            "EXTRA_PACKAGES": "pkg1 pkg2",
            "CALLS_LOG": str(calls_log),
        }
    )

    result = subprocess.run(
        ["bash", script_path.as_posix()],
        cwd=tmp_path,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout

    def escape_for_sudoers(path_str: str) -> str:
        specials = set("!@#$%^&*(){}[]:;|<>,?~")
        escaped = path_str.replace("\\", "\\\\").replace(" ", r"\ ")
        escaped = "".join(f"\\{ch}" if ch in specials else ch for ch in escaped)
        return escaped

    sudoers_content = sudoers_path.read_text().strip()
    expected_path = escape_for_sudoers(str(script_path))
    assert sudoers_content == f"tester ALL=(root) NOPASSWD: {expected_path}"

    conf50 = apt_conf_dir / "50unattended-upgrades"
    conf20 = apt_conf_dir / "20auto-upgrades"
    assert conf50.exists() and conf20.exists()
    assert 'Unattended-Upgrade::Automatic-Reboot-Time "03:30";' in conf50.read_text()

    setup_log = (tmp_path / "logs" / "setup.log")
    assert setup_log.exists()
    assert "Starting Unattended Setup" in setup_log.read_text()

    dryrun_log = (tmp_path / "logs" / "dryrun.log")
    assert dryrun_log.exists()

    calls = calls_log.read_text()
    assert "apt-get update" in calls
    assert "apt-get install -y unattended-upgrades apt-listchanges" in calls
    assert "unattended-upgrade --dry-run --debug" in calls


def test_allowed_origins_sanitized(tmp_path: Path) -> None:
    stub_dir = tmp_path / "stubs"
    stub_dir.mkdir()
    calls_log = tmp_path / "calls.log"
    calls_log.touch()

    _make_stubs(stub_dir, calls_log)

    script_copy_dir = tmp_path / "path with space"
    script_copy_dir.mkdir()
    script_path = script_copy_dir / "autoupdate.sh"
    shutil.copy(SCRIPT_SRC, script_path)
    script_path.chmod(0o755)

    apt_conf_dir = tmp_path / "aptconf"
    apt_conf_dir.mkdir()

    sudoers_path = tmp_path / "sudoers" / "autoupdate"
    sudoers_path.parent.mkdir(parents=True)

    env = os.environ.copy()
    env.update(
        {
            "PATH_OVERRIDE": f"{stub_dir}{os.pathsep}/usr/sbin:/usr/bin:/sbin:/bin",
            "SKIP_ROOT_CHECK": "true",
            "LOG_DIR": str(tmp_path / "logs"),
            "APT_CONF_DIR": str(apt_conf_dir),
            "SUDOERS_TARGET": str(sudoers_path),
            "TARGET_USER": "tester",
            "ENABLE_NOPASSWD": "true",
            "EXTRA_PACKAGES": "pkg1 pkg2",
            # Inject an invalid origin (no colon) plus valid ones; invalid must be skipped.
            "ALLOWED_EXTRA_ORIGINS": "linux.abitti.fi:ytl-linux invalid_entry linux.abitti.fi:ytl-linux-digabi2-examnet",
            "ALLOWED_EXTRA_PATTERNS": "site=linux.abitti.fi",
        }
    )

    result = subprocess.run(
        ["bash", script_path.as_posix()],
        cwd=tmp_path,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout

    conf50 = apt_conf_dir / "50unattended-upgrades"
    content = conf50.read_text().splitlines()

    # Collect Allowed-Origins entries
    allowed = []
    in_allowed = False
    for line in content:
        if "Allowed-Origins" in line:
            in_allowed = True
            continue
        if in_allowed and "};" in line:
            in_allowed = False
            continue
        if in_allowed:
            line = line.strip().strip('";')
            if line:
                allowed.append(line)

    assert "linux.abitti.fi:ytl-linux" in allowed
    assert "linux.abitti.fi:ytl-linux-digabi2-examnet" in allowed
    assert "invalid_entry" not in allowed
    # Ensure every allowed entry has a colon
    assert all(":" in a for a in allowed)

    # Collect Origins-Pattern entries
    patterns = []
    in_pat = False
    for line in content:
        if "Origins-Pattern" in line:
            in_pat = True
            continue
        if in_pat and "};" in line:
            in_pat = False
            continue
        if in_pat:
            line = line.strip().strip('";')
            if line:
                patterns.append(line)

    assert "site=linux.abitti.fi" in patterns

