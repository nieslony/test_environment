$win_version = "2k22"
$driver_disk = "E:"

Write-Host "Import RedHat Certificates"
$DriverPath = Get-Item "${driver_disk}\*\2k22"
$CertStore = Get-Item "cert:\LocalMachine\TrustedPublisher"
$CertStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
Get-ChildItem -Recurse -Path $DriverPath -Filter "*.cat" | % {
    $Cert = (Get-AuthenticodeSignature $_.FullName).SignerCertificate
    Write-Host ( "Added {0}, {1} from {2}" -f $Cert.Thumbprint,$Cert.Subject,$_.FullName )
    $CertStore.Add($Cert)
}
$CertStore.Close()

Write-Host "Install All Drivers from E:"
Get-ChildItem "${driver_disk}\" -Recurse -Include @($win_version, "w11") `
    | ForEach-Object `
        {
            $dir = $_.FullName
            Get-ChildItem $dir -Recurse -Filter "*inf" `
                | ForEach-Object `
                    {
                        $infFile = $_.FullName
                        Write-Host "Install driver from $infFile"
                        pnputil /add-driver $infFile /install
                    }
        }

foreach ($msi in "guest-agent/qemu-ga-x86_64.msi", "virtio-win-gt-x64.msi") {
    $fullPath = "${driver_disk}\${msi}"
    Write-Host "Installing $fullPath"
    Start-Process "msiexec" -ArgumentList "/package", $fullPath, "/passive" -Wait
}

Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
