Write-Host -ForegroundColor White "Configure Basic Auth for WinRM"
winrm quickconfig -q | Out-Null
winrm get winrm/config > "${env:TEMP}\secpol-before.txt"
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="512"}' | Out-Null
winrm set winrm/config '@{MaxTimeoutms="1800000"}' | Out-Null
winrm set winrm/config/service '@{AllowUnencrypted="true"}' | Out-Null
winrm set winrm/config/service/auth '@{Basic="true"}' | Out-Null
winrm set winrm/config/client/auth '@{Basic="true"}' | Out-Null
winrm get winrm/config > "${env:TEMP}\secpol-after.txt"
diff (cat "${env:TEMP}\secpol-before.txt") (cat "${env:TEMP}\secpol-after.txt")
