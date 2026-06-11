<#
.SYNOPSIS
  Remediate Intune device enrollment/compliance issues.

.PARAMETER DeviceId
  The Intune managedDevice id (GUID).

.NOTES
  Requires: Managed identity or service principal with DeviceManagementManagedDevices.ReadWrite.All
  Modules: Microsoft.Graph.DeviceManagement.ManagedDevices
#>

param(
  [Parameter(Mandatory=$true)]
  [string] $DeviceId,

  [switch] $WhatIf
)

# Authenticate using managed identity (Azure Automation managed identity)
try {
  Connect-MgGraph -Scopes "DeviceManagementManagedDevices.ReadWrite.All" -ErrorAction Stop
} catch {
  Write-Error "Graph authentication failed: $_"
  exit 2
}

function Try-RemoteSync {
  param($id)
  try {
    Invoke-MgDeviceManagementManagedDeviceSyncDevice -ManagedDeviceId $id -ErrorAction Stop
    Write-Output "Sync requested for $id"
    return $true
  } catch {
    Write-Warning "Remote sync failed: $_"
    return $false
  }
}

function Get-DeviceStatus {
  param($id)
  try {
    return Get-MgDeviceManagementManagedDevice -ManagedDeviceId $id -ErrorAction Stop
  } catch {
    Write-Warning "Failed to get device status: $_"
    return $null
  }
}

# 1) Try remote sync
if (-not $WhatIf) {
  #$syncOk = Try-RemoteSync -id $DeviceId
  # before: $syncOk = Try-RemoteSync -id $DeviceId
# use it:
$syncOk = Try-RemoteSync -id $DeviceId
if (-not $syncOk) {
  Write-Warning "Remote sync request failed for $DeviceId"
}
  Start-Sleep -Seconds 20
  $status = Get-DeviceStatus -id $DeviceId
  if ($status -and $status.EnrollmentState -eq "Enrolled" -and $status.ComplianceState -eq "Compliant") {
    Write-Output "Device $DeviceId is healthy after sync."
    Disconnect-MgGraph
    exit 0
  }
}

# 2) Push device script (device management script) to run local repair
# This section assumes you have pre-created a deviceManagementScript in Intune and know its id.
# Alternatively, create/update the script here and assign to the device.
$scriptId = "<REPLACE_WITH_PRECREATED_SCRIPT_ID>"

if ($scriptId -eq "<REPLACE_WITH_PRECREATED_SCRIPT_ID>") {
  Write-Warning "No deviceManagementScript id configured. Skipping push step."
  Disconnect-MgGraph
  exit 3
}

try {
  # Create a run request
  $runReq = Invoke-MgDeviceManagementDeviceManagementScriptRun -DeviceManagementScriptId $scriptId -ManagedDeviceIds @($DeviceId)
  Write-Output "Triggered device script run: $($runReq.Id)"
} catch {
  Write-Warning "Failed to trigger device script: $_"
  Disconnect-MgGraph
  exit 4
}

# Poll for result (simple loop)
$attempts = 0
while ($attempts -lt 12) {
  Start-Sleep -Seconds 15
  $attempts++
  # Query device run states (simplified)
  try {
    $runs = Get-MgDeviceManagementDeviceManagementScriptDeviceRunSummary -DeviceManagementScriptId $scriptId -ErrorAction Stop
    # examine $runs for the device and status
    $deviceRun = $runs.value | Where-Object { $_.managedDeviceId -eq $DeviceId }
    if ($deviceRun) {
      Write-Output "Device script run state: $($deviceRun.status)"
    }
    # Note: In production, query the specific device run status via the appropriate Graph endpoint
    Write-Output "Polled run summary (attempt $attempts)"
  } catch {
    Write-Warning "Polling failed: $_"
  }
}

# Final status check
$status = Get-DeviceStatus -id $DeviceId
if ($status -and $status.EnrollmentState -eq "Enrolled" -and $status.ComplianceState -eq "Compliant") {
  Write-Output "Remediation succeeded for $DeviceId"
  Disconnect-MgGraph
  exit 0
} else {
  Write-Error "Remediation failed for $DeviceId"
  Disconnect-MgGraph
  exit 5
}

# Dot-source ServiceNow helper (adjust path if needed)
. $PSScriptRoot\servicenow.ps1

# After final remediation check fails
$status = Get-DeviceStatus -id $DeviceId
if ($status -and $status.EnrollmentState -eq "Enrolled" -and $status.ComplianceState -eq "Compliant") {
  Write-Output "Remediation succeeded for $DeviceId"
  # Log success to Log Analytics (placeholder)
  # Send-LogAnalyticsEvent -WorkspaceId $workspaceId -Payload ...
  Disconnect-MgGraph
  exit 0
} else {
  Write-Error "Remediation failed for $DeviceId"

  # 1) Write a local log entry (for debugging / CI)
  $logLine = "$(Get-Date -Format o) ERROR Remediation failed for deviceId=$DeviceId; status=$($status | ConvertTo-Json -Depth 2)"
  $localLogPath = Join-Path $PSScriptRoot "..\logs\remediation.log"
  try {
    Add-Content -Path $localLogPath -Value $logLine -ErrorAction SilentlyContinue
  } catch {
    Write-Warning "Unable to write local log: $_"
  }

  # 2) Send structured event to Log Analytics (recommended)
  # Placeholder: implement Log Analytics ingestion here (use workspace id/key or Az module)
  # Example: Send-LogAnalyticsEvent -WorkspaceId $LA_WORKSPACE -Payload @{ deviceId=$DeviceId; outcome='failed'; details=$status }

  # 3) Create ServiceNow incident (escalation)
  $short = "Intune remediation failed for device $DeviceId"
  $desc  = "Automated remediation failed for device $DeviceId. EnrollmentState=$($status.EnrollmentState); ComplianceState=$($status.ComplianceState). See runbook logs."
  $incidentId = New-ServiceNowIncident -ShortDescription $short -Description $desc -Priority "2"

  if ($incidentId) {
    Write-Output "Created ServiceNow incident: $incidentId"
  } else {
    Write-Warning "ServiceNow incident creation failed or was skipped."
  }

  Disconnect-MgGraph
  exit 5
}

# Dot-source helpers (assumes same folder)
. $PSScriptRoot\loganalytics.ps1
. $PSScriptRoot\servicenow_oauth.ps1

# Final status check
$status = Get-DeviceStatus -id $DeviceId
if ($status -and $status.EnrollmentState -eq "Enrolled" -and $status.ComplianceState -eq "Compliant") {
  Write-Output "Remediation succeeded for $DeviceId"

  # Send success event to Log Analytics
  $payload = @{
    timestamp = (Get-Date).ToString("o")
    deviceId  = $DeviceId
    outcome   = "success"
    enrollmentState = $status.EnrollmentState
    complianceState = $status.ComplianceState
  }
  Send-LogAnalyticsEvent -Payload $payload -LogType "IntuneSelfHeal"

  Disconnect-MgGraph
  exit 0
} else {
  Write-Error "Remediation failed for $DeviceId"

  # Local log
  $logLine = "$(Get-Date -Format o) ERROR Remediation failed for deviceId=$DeviceId; status=$($status | ConvertTo-Json -Depth 3)"
  $localLogPath = Join-Path $PSScriptRoot "..\logs\remediation.log"
  try { Add-Content -Path $localLogPath -Value $logLine -ErrorAction SilentlyContinue } catch {}

  # Send failure event to Log Analytics
  $payload = @{
    timestamp = (Get-Date).ToString("o")
    deviceId  = $DeviceId
    outcome   = "failed"
    enrollmentState = if ($status) { $status.EnrollmentState } else { "unknown" }
    complianceState = if ($status) { $status.ComplianceState } else { "unknown" }
    runbook = "remediate-intune"
  }
  Send-LogAnalyticsEvent -Payload $payload -LogType "IntuneSelfHeal"

  # Create ServiceNow incident via OAuth
  $short = "Intune remediation failed for device $DeviceId"
  $desc  = "Automated remediation failed for device $DeviceId. EnrollmentState=$($status.EnrollmentState); ComplianceState=$($status.ComplianceState). See runbook logs."
  $incidentId = New-ServiceNowIncidentOAuth -ShortDescription $short -Description $desc -Priority "2"

  if ($incidentId) {
    Write-Output "Created ServiceNow incident: $incidentId"
  } else {
    Write-Warning "ServiceNow incident creation failed or was skipped."
  }

  Disconnect-MgGraph
  exit 5
}
