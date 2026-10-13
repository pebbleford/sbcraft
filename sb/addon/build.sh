#!/bin/bash
# Builds SBCraft.addon64 from Git Bash (runs build.bat through cmd).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
cmd //c "$(cygpath -w "$HERE/build.bat")"
