function Log-Message ($msg) {
    Write-Host "===== $msg =====".PadRight(80, "=")
}

Log-Message "Set Execution Policy"
#Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -force

Log-Message "Install Package Provider NuGet"
Install-PackageProvider -Name NuGet -Force

Log-Message "Install Module"
Install-Module -Name PSWindowsUpdate -Force

Log-Message "Import Module"
Import-Module PSWindowsUpdate

Log-Message "Install Updates"
Get-WindowsUpdate -AcceptAll -Install -AutoReboot
