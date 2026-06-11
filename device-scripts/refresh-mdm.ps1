<#
Local device remediation script: refresh MDM token and restart Intune services.
Designed to be safe and idempotent.
#>

Try {
  Write-Output "Stopping Intune Management Extension"
  Stop-Service -Name "IntuneManagementExtension" -ErrorAction SilentlyContinue -Force

  Write-Output "Removing stale token cache if present"
  $tokenPath = "C:\ProgramData\Microsoft\MDM\TokenCache"
  if (Test-Path $tokenPath) {
    Remove-Item -Path $tokenPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "Removed $tokenPath"
  } else {
    Write-Output "No token cache found"
  }

  Write-Output "Restarting services"
  Start-Service -Name "IntuneManagementExtension" -ErrorAction SilentlyContinue
  Start-Service -Name "dmwappushservice" -ErrorAction SilentlyContinue

  Write-Output "Triggering enrollment refresh"
  $enroller = "$env:windir\System32\DeviceEnroller.exe"
  if (Test-Path $enroller) {
    Start-Process -FilePath $enroller -ArgumentList "/c" -NoNewWindow -ErrorAction SilentlyContinue
    Write-Output "Triggered DeviceEnroller"
  } else {
    Write-Warning "DeviceEnroller.exe not found"
  }

  Write-Output "Local remediation completed successfully"
  exit 0
} Catch {
  Write-Error "Local remediation failed: $_"
  exit 1
}
