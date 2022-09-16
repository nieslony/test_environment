Import-Module ActiveDirectory

$userCount = 1..5
$waitTime = 30

function Log-Message ($msg) {
    Write-Host "===== $msg =====".PadRight(80, "=")
}

Log-Message "Waiting for service Active Directory Web Services"
$found = $false
Do {
    try {
        Get-ADUser Administrator
        $found = $true
    }
    catch [Microsoft.ActiveDirectory.Management.ADServerDownException] {
        Write-Host "Active Directory Web Services not yet running. Let's wait $waitTime s."
        Start-Sleep -s $waitTime
    }
}
Until ($found)

Log-Message "Set time server"
w32tm.exe /config /syncfromflags:manual /manualpeerlist:at.pool.ntp.org,0x8 /reliable:yes /update

Log-Message "Creating test users"
foreach ($i in $userCount) {
    $username = "user$i"
    $password = "Us.erPassword.$i" | ConvertTo-SecureString -AsPlainText -Force
    Write-Host "Creating $username"
    New-ADUSer `
        -Name $username `
        -DisplayName "User $i" `
        -Enabled $true `
        -ChangePasswordAtLogon $false `
        -AccountPassword $password `
        -passThru `
        -Server "dc01.windows.lab"
}

Log-Message "Add Administrator to 'incoming forest trust builders'"
Add-ADGroupMember -Identity "incoming forest trust builders" Administrator

Log-Message "Create reverse Zone"
Add-DnsServerPrimaryZone `
    -NetworkID "192.168.110.0/24" `
    -ReplicationScope "Forest" `
    -DynamicUpdate "Secure"

Log-Message "Add conditional forwarders"
Add-DnsServerConditionalForwarderZone `
    -Name "linux.lab" `
    -MasterServer "192.168.120.20"
Add-DnsServerConditionalForwarderZone `
    -Name "120.168.192.in-addr.arpa" `
    -MasterServer "192.168.120.20"

Log-Message "Disable listen on management ip for DNS"
$dnsServerSetting = Get-DnsServerSetting -All
$managementIp = (Get-NetIpAddress -IpAddress "192.168.121.*").IpAddress
$listen = @("127.0.0.1")
$dnsServerSetting.ListeningIpAddress.ForEach({
    if ($_ -ne $managementIp) {
        $listen += $_
    }
})
$dnsServerSetting.ListeningIpAddress = $listen
