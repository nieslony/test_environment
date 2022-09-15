function Log-Message ($msg) {
    Write-Host "===== $msg =====".PadRight(80, "=")
}

$my_hostname = [System.Net.Dns]::GetHostName()
$my_mgmt_ip = (Get-NetIpAddress -IpAddress "192.168.121.*" | Select IpAddress).IpAddress

Log-Message "Remove default route to admin interface"
Remove-NetRoute `
    -DestinationPrefix "0.0.0.0/0" `
    -NextHop "192.168.121.1" `
    -Confirm:$false

Log-Message "Avoid DNS updates for admin interface"
Get-NetIpAddress -IpAddress "192.168.121.*" | Set-NetIpAddress -SkipAsSource $true

try {
    Log-Message "Remove DNS entry $hostname => $my_mgmt_ip"
    Remove-DnsServerResourceRecord `
        -ZoneName "windows.lab" `
        -Name $my_hostname `
        -RecordData $my_mgmt_ip `
        -RRType "A" `
        -Force
} catch {
    Write-Host "Cannot remove DNS entry: $($_.Exception)"
}

Log-Message "Disallow DNS updates on management interface"
$my_mgmt_if_nr = (Get-NetIpAddress -IpAddress "192.168.121.*").InterfaceIndex
$my_mgmt_if_guid = (Get-NetAdapter -InterfaceIndex $my_mgmt_if_nr).InterfaceGuid
$itemName = "DisableDynamicUpdate"
$reg_path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$my_mgmt_if_guid"
if ((Get-ItemProperty -Path $reg_path -Name $itemName -ErrorAction Ignore) -eq $null) {
    Write-Host "New item  ${reg_path}.${itemName} = 1"
    New-ItemProperty -Path $reg_path -Name "DisableDynamicUpdate" -Value 1 -PropertyType "DWord"
}
else {
    Write-Host "Updating ${reg_path}.${itemName} = 1"
    Set-ItemProperty -Path $reg_path -Name "DisableDynamicUpdate" -Value 1
}
