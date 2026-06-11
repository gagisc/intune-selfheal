<#
Query Intune managed devices for problematic state.
Requires Microsoft.Graph.DeviceManagement.ManagedDevices permissions.
#>

param(
  [string] $OemFilter = "ContosoOEM",
  [int] $MaxResults = 200
)

Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All"

# Example filter: enrollmentState not Enrolled OR complianceState not Compliant AND deviceManufacturer eq 'ContosoOEM'
$filter = "((enrollmentState ne 'Enrolled') or (complianceState ne 'Compliant')) and (deviceManufacturer eq '$OemFilter')"

$devices = Get-MgDeviceManagementManagedDevice -Filter $filter -Top $MaxResults

if ($devices) {
  $devices | Select-Object id, deviceName, enrollmentState, complianceState, deviceManufacturer | ConvertTo-Json -Depth 3
} else {
  Write-Output "No matching devices"
}

Disconnect-MgGraph
