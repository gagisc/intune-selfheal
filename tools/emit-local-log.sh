#!/usr/bin/env bash
# Emit a sample remediation log entry for local testing
mkdir -p logs
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) INFO Remediation run started for deviceId=00000000-0000-0000-0000-000000000000" >> logs/remediation.log
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) ERROR Remediation failed for deviceId=00000000-0000-0000-0000-000000000000; reason=script-run-failed" >> logs/remediation.log
echo "Wrote logs/remediation.log"
