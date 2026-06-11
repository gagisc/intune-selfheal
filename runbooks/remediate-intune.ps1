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

  [switch] $WhatIf,

  [string] $DeviceScriptId = $env:INTUNE_DEVICE_SCRIPT_ID
)

# Authenticate using managed identity (Azure Automation managed identity)
try {
  Connect-MgGraph -Scopes "DeviceManagementManagedDevices.ReadWrite.All" -ErrorAction Stop
} catch {
  Write-Error "Graph authentication failed: $_"
  exit 2
}

function Invoke-RemoteSync {
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
  $syncOk = Invoke-RemoteSync -id $DeviceId
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
if ([string]::IsNullOrWhiteSpace($DeviceScriptId)) {
  Write-Warning "No deviceManagementScript id configured. Skipping push step."
  Disconnect-MgGraph
  exit 3
}

try {
  # Create a run request
  $runReq = Invoke-MgDeviceManagementDeviceManagementScriptRun -DeviceManagementScriptId $DeviceScriptId -ManagedDeviceIds @($DeviceId)
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
    $runs = Get-MgDeviceManagementDeviceManagementScriptDeviceRunSummary -DeviceManagementScriptId $DeviceScriptId -ErrorAction Stop
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
