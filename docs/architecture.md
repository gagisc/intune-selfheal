# Intune Self-Heal Architecture

**Components**
- Detector: scheduled Graph query (Azure Monitor or Logic App) to find devices in bad state.
- Orchestrator: Logic App that iterates devices and calls Azure Automation runbook.
- Runbook: PowerShell runbook `remediate-intune.ps1` that attempts remote sync then triggers device script.
- Device script: `refresh-mdm.ps1` executed on device via Intune deviceManagementScript.
- Observability: Log Analytics + Grafana dashboard; Logic App logs run results; ServiceNow integration for escalations.

**Design principles**
- Small composable pieces (Unix philosophy).
- Idempotent device scripts.
- Rate limiting and batching to avoid Graph throttling.
- Dry-run support and audit logs for all actions.
