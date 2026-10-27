#!/bin/sh
# Shortcut to flash Stock firmware on Notion P298 (ASR1802S)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
exec "$SCRIPT_DIR/flash.sh" stock "$@"
