#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$project_root/scripts/build-app.sh"
open "$project_root/build/CodexQuotaNotch.app"
