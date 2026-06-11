<#
.SYNOPSIS
  Create a ServiceNow incident via REST API.

.NOTES
  - Use Azure Key Vault or Automation account variables for credentials.
  - This helper returns the created incident sys_id on success.
#>

function New-ServiceNowIncident {
  param(
    [Parameter(Mandatory=$true)][string] $ShortDescription,
    [Parameter(Mandatory=$true)][string] $Description,
    [string] $Category = "IT Operations",
    [string] $Priority = "3"
  )

  # Placeholder: retrieve credentials from Key Vault or Automation variables
  $snInstance = "<SERVICENOW_INSTANCE>"            # e.g., dev123.service-now.com
  $snUser = "<SERVICENOW_USER>"
  $snPass = "<SERVICENOW_PASSWORD>"

  if ($snInstance -like "<*>" -or $snUser -like "<*>" -or $snPass -like "<*>") {
    Write-Warning "ServiceNow credentials not configured. Skipping incident creation."
    return $null
  }

  $uri = "https://$snInstance/api/now/table/incident"
  $body = @{
    short_description = $ShortDescription
    description       = $Description
    category          = $Category
    priority          = $Priority
    caller_id         = "automation"
  } | ConvertTo-Json

  $pair = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$snUser`:$snPass"))
  $headers = @{
    Authorization = "Basic $pair"
    Accept        = "application/json"
    "Content-Type" = "application/json"
  }

  try {
    $resp = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop
    $sysId = $resp.result.sys_id
    Write-Output $sysId
    return $sysId
  } catch {
    Write-Warning "Failed to create ServiceNow incident: $_"
    return $null
  }
}
