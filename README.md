# Intune Self-Heal

This repository contains a small, composable automation to detect and remediate Intune enrollment/compliance issues.

## Contents
- `runbooks/remediate-intune.ps1` — Azure Automation runbook.
- `device-scripts/refresh-mdm.ps1` — local device remediation script.
- `tools/query-intune-devices.ps1` — detector script for testing.
- `azure/logicapp-workflow.json` — skeleton Logic App workflow.
- `.github/workflows/validate.yml` — CI validation workflow.

## Quick start
1. Create an Azure Automation account and import `runbooks/remediate-intune.ps1`.
2. Create a deviceManagementScript in Intune with `device-scripts/refresh-mdm.ps1` and note its id.
3. Update the runbook with the script id and configure managed identity permissions.
4. Deploy the Logic App (or use Azure Monitor + Logic App) to call the runbook on a schedule.
5. Push this repo and let the CI validate files.

## Safety
- Test in a pilot group first.
- Use `-WhatIf` or dry-run modes before enabling full remediation.

# Logs and Observability

**Purpose**
This folder documents where remediation logs are stored and how to access them.

**Primary logging targets**
- **Azure Log Analytics** (recommended): runbooks should write structured events to Log Analytics via the Azure Monitor HTTP Data Collector API or Az.OperationalInsights module.
- **Local file (for testing)**: `logs/remediation.log` — used only for local testing and CI smoke tests.

**Retention and rotation**
- Production logs are retained in Log Analytics and managed by workspace retention settings.
- Local log files are rotated by CI/test scripts and not used in production.

**Security**
- Do not commit secrets. Use Azure Key Vault or managed identity for ServiceNow credentials and Graph tokens.
