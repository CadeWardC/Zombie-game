#!/bin/sh
# Runs the two-device multiplayer test: a host and a guest on this machine.
# Usage: tests/run_net_test.sh [path-to-godot]
GODOT="${1:-godot}"
cd "$(dirname "$0")/.." || exit 1
"$GODOT" --headless res://tests/net_test.tscn -- --role=host > /tmp/net_host.log 2>&1 &
HOST=$!
sleep 2
"$GODOT" --headless res://tests/net_test.tscn -- --role=client > /tmp/net_client.log 2>&1 &
CLIENT=$!
wait $HOST; H=$?
wait $CLIENT; C=$?
grep -h "^\[" /tmp/net_host.log /tmp/net_client.log
grep -h "SCRIPT ERROR" -A2 /tmp/net_host.log /tmp/net_client.log | head -40
echo "host exit $H, guest exit $C"
[ "$H" -eq 0 ] && [ "$C" -eq 0 ]
