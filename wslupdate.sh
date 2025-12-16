#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

EXTRA_PACKAGES="${EXTRA_PACKAGES:-ytl-linux-digabi2-wsl}"
export EXTRA_PACKAGES

exec bash "${script_dir}/autoupdate.sh" "$@"
