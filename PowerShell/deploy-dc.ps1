param($adminpassword)

$domainName = "windows.lab"
$netBiosName = "WINDOWS_LAB"
$domainNetbiosName = "WINDOWS_LAB"
$safeModeAdministratorPassword = $adminpassword `
    | ConvertTo-SecureString -AsPlainText -Force

$newIpAddress = "192.168.110.20"
$newPrefix = $newIpAddress.split(".")[0..2] -join "."
$searchIp = $newPrefix + ".*"
$prefixLength = 24
$gateway = $newPrefix + ".254"

function Log-Message ($msg) {
    Write-Host "===== $msg =====".PadRight(80, "=")
}

Log-Message "Set static IP $newIpAddress"
Get-NetIpAddress -IpAddress $searchIp `
    | New-NetIpAddress `
        -IpAddress $newIpAddress `
        -PrefixLength $prefixLength `
        -DefaultGateway $gateway
# Get-NetIpAddress -IpAddress $searchIp `
#     | Set-DnsClient
#         -ConnectionSpecificSuffix $domainName

$ManagementNicIndex = Get-NetIpAddress -Ipaddress "192.168.121.*" `
    | Select InterfaceIndex

Log-Message "Set Administrator password"
Set-LocalUser `
    -Name "Administrator" `
    -Password $safeModeAdministratorPassword `
    -PasswordNeverExpires:$true `
    -Confirm:$false

Log-Message "Install Feature AD Domain Services"
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

Log-Message "Deploy Domain Forest"
Install-ADDSForest `
     -DomainName $domainName `
     -DomainNetbiosName $netBiosName `
     -SafeModeAdministratorPassword $safeModeAdministratorPassword `
     -InstallDns:$true `
     -Confirm:$false `
     -DomainMode "WinThreshold" `
     -ForestMode "WinThreshold" `
     -NoRebootOnCompletion:$false
