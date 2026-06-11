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
    [string] $Priority = "3",
    [string] $Instance = $env:SERVICENOW_INSTANCE,
    [System.Management.Automation.PSCredential] $Credential,
    [string] $CredentialName = $env:SERVICENOW_CREDENTIAL_ASSET
  )

  if (-not $Credential) {
    if (-not [string]::IsNullOrWhiteSpace($CredentialName) -and (Get-Command Get-AutomationPSCredential -ErrorAction SilentlyContinue)) {
      $Credential = Get-AutomationPSCredential -Name $CredentialName
    }

    if (-not $Credential) {
      Write-Warning "ServiceNow credentials not configured. Skipping incident creation."
      return $null
    }
  }

  if ([string]::IsNullOrWhiteSpace($Instance)) {
    Write-Warning "ServiceNow credentials not configured. Skipping incident creation."
    return $null
  }

  $uri = "https://$Instance/api/now/table/incident"
  $body = @{
    short_description = $ShortDescription
    description       = $Description
    category          = $Category
    priority          = $Priority
    caller_id         = "automation"
  } | ConvertTo-Json

  $pair = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Credential.UserName)`:$($Credential.GetNetworkCredential().Password)"))
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
