<#
.SYNOPSIS
  Send structured events to Azure Log Analytics via the HTTP Data Collector API.

.DESCRIPTION
  Uses Azure Key Vault to retrieve the workspace id and primary key.
  Designed for use inside Azure Automation runbooks using a managed identity.

.PARAMETER Payload
  A hashtable or PSCustomObject representing the event to send.

.EXAMPLE
  Send-LogAnalyticsEvent -Payload @{ deviceId = $DeviceId; outcome = 'failed'; details = $status }
#>

function Send-LogAnalyticsEvent {
  param(
    [Parameter(Mandatory=$true)]
    [object] $Payload,

    [string] $LogType = "IntuneSelfHeal"
  )

  # Key Vault and secret names - replace or set via Automation variables
  $kvName = $env:KV_NAME  # e.g., "intune-selfheal-kv"
  $workspaceSecretName = $env:LA_WORKSPACE_ID_SECRET  # e.g., "la-workspace-id"
  $workspaceKeySecretName = $env:LA_WORKSPACE_KEY_SECRET  # e.g., "la-primary-key"

  if (-not $kvName -or -not $workspaceSecretName -or -not $workspaceKeySecretName) {
    Write-Warning "Log Analytics Key Vault configuration missing. Set KV_NAME, LA_WORKSPACE_ID_SECRET, LA_WORKSPACE_KEY_SECRET as environment variables or Automation variables."
    return $false
  }

  try {
    # Acquire token for Key Vault using managed identity
    $token = (Invoke-RestMethod -Method Get -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" -Headers @{Metadata="true"}).access_token
    $kvUri = "https://$kvName.vault.azure.net/secrets/$workspaceSecretName?api-version=7.3"
    $workspaceIdResp = Invoke-RestMethod -Method Get -Uri $kvUri -Headers @{ Authorization = "Bearer $token" }
    $workspaceId = $workspaceIdResp.value

    $kvKeyUri = "https://$kvName.vault.azure.net/secrets/$workspaceKeySecretName?api-version=7.3"
    $workspaceKeyResp = Invoke-RestMethod -Method Get -Uri $kvKeyUri -Headers @{ Authorization = "Bearer $token" }
    $workspaceKey = $workspaceKeyResp.value
  } catch {
    Write-Warning "Failed to retrieve Log Analytics secrets from Key Vault: $_"
    return $false
  }

  if (-not $workspaceId -or -not $workspaceKey) {
    Write-Warning "Log Analytics workspace id or key empty."
    return $false
  }

  # Build request
  $customerId = $workspaceId
  $sharedKey = $workspaceKey
  $body = if ($Payload -is [string]) { $Payload } else { ($Payload | ConvertTo-Json -Depth 6) }
  $contentLength = [System.Text.Encoding]::UTF8.GetByteCount($body)
  $rfc1123date = (Get-Date).ToUniversalTime().ToString("R")
  $signature = "POST`n$contentLength`napplication/json`nx-ms-date:$rfc1123date`n/api/logs"
  $bytesToHash = [Text.Encoding]::UTF8.GetBytes($signature)
  $keyBytes = [Convert]::FromBase64String($sharedKey)
  $hash = [System.Security.Cryptography.HMACSHA256]::new($keyBytes).ComputeHash($bytesToHash)
  $encodedHash = [Convert]::ToBase64String($hash)
  $auth = "SharedKey $customerId:$encodedHash"

  $uri = "https://$customerId.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"

  try {
    $headers = @{
      "Authorization" = $auth
      "Log-Type"      = $LogType
      "x-ms-date"     = $rfc1123date
      "time-generated-field" = ""
      "Content-Type"  = "application/json"
    }
    $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -ErrorAction Stop
    Write-Output "Log Analytics ingestion accepted"
    return $true
  } catch {
    Write-Warning "Failed to send event to Log Analytics: $_"
    return $false
  }
}
