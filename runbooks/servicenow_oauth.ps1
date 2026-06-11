<#
.SYNOPSIS
  Create a ServiceNow incident using OAuth client credentials.

.DESCRIPTION
  Retrieves ServiceNow OAuth client id/secret and instance name from Azure Key Vault.
  Uses managed identity to access Key Vault. Returns the created incident sys_id on success.

.PARAMETER ShortDescription
  Short description for the incident.

.PARAMETER Description
  Detailed description.

.PARAMETER Priority
  Incident priority (1-5).
#>

function New-ServiceNowIncidentOAuth {
  param(
    [Parameter(Mandatory=$true)][string] $ShortDescription,
    [Parameter(Mandatory=$true)][string] $Description,
    [string] $Priority = "3",
    [string] $Category = "IT Operations"
  )

  # Key Vault and secret names - set via environment or Automation variables
  $kvName = $env:KV_NAME
  $snInstanceSecret = $env:SN_INSTANCE_SECRET      # e.g., "sn-instance"
  $snClientIdSecret = $env:SN_CLIENT_ID_SECRET     # e.g., "sn-client-id"
  $snClientSecretSecret = $env:SN_CLIENT_SECRET_SECRET  # e.g., "sn-client-secret"
  $snTokenUrlSecret = $env:SN_TOKEN_URL_SECRET     # optional override for token endpoint

  if (-not $kvName -or -not $snInstanceSecret -or -not $snClientIdSecret -or -not $snClientSecretSecret) {
    Write-Warning "ServiceNow Key Vault configuration missing. Set KV_NAME and ServiceNow secret names as environment variables."
    return $null
  }

  try {
    # Get Key Vault token via managed identity
    $token = (Invoke-RestMethod -Method Get -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" -Headers @{Metadata="true"}).access_token

    $instanceResp = Invoke-RestMethod -Method Get -Uri "https://$kvName.vault.azure.net/secrets/$snInstanceSecret?api-version=7.3" -Headers @{ Authorization = "Bearer $token" }
    $snInstance = $instanceResp.value.Trim()

    $clientIdResp = Invoke-RestMethod -Method Get -Uri "https://$kvName.vault.azure.net/secrets/$snClientIdSecret?api-version=7.3" -Headers @{ Authorization = "Bearer $token" }
    $clientId = $clientIdResp.value.Trim()

    $clientSecretResp = Invoke-RestMethod -Method Get -Uri "https://$kvName.vault.azure.net/secrets/$snClientSecretSecret?api-version=7.3" -Headers @{ Authorization = "Bearer $token" }
    $clientSecret = $clientSecretResp.value.Trim()

    if ($snTokenUrlSecret) {
      $tokenUrlResp = Invoke-RestMethod -Method Get -Uri "https://$kvName.vault.azure.net/secrets/$snTokenUrlSecret?api-version=7.3" -Headers @{ Authorization = "Bearer $token" }
      $tokenUrl = $tokenUrlResp.value.Trim()
    } else {
      $tokenUrl = "https://$snInstance/oauth_token.do"
    }
  } catch {
    Write-Warning "Failed to retrieve ServiceNow secrets from Key Vault: $_"
    return $null
  }

  if (-not $snInstance -or -not $clientId -or -not $clientSecret) {
    Write-Warning "ServiceNow instance or credentials missing."
    return $null
  }

  try {
    # Acquire OAuth token from ServiceNow
    $tokenResp = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body @{ grant_type = "client_credentials" } -Headers @{ Authorization = ("Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$clientId`:$clientSecret"))) } -ErrorAction Stop
    $accessToken = $tokenResp.access_token
  } catch {
    Write-Warning "Failed to acquire ServiceNow OAuth token: $_"
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

  $headers = @{
    Authorization = "Bearer $accessToken"
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
