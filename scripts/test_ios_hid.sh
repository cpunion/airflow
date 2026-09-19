#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
cargo build -p airflow-core --example hid_probe_codec
swift build --product AirFlowHIDProbe
exec .build/debug/AirFlowHIDProbe "${1:---interactive}" "$PWD/target/debug/examples/hid_probe_codec"
