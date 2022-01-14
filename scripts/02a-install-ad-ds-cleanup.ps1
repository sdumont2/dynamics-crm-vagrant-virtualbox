###########################################################################
# Installing Active directory forest and other domain controller services #
###########################################################################
Param(
    [String]$IPAddress,
    [String]$GatewayIP,
    [String]$ContosoIPAddressPattern,
    [String]$NetbiosName,
    $vagrantUsername,
    $plaintextPass
)
Set-ExecutionPolicy Bypass -Scope Process

Restart-Service nlasvc -Force 

##############################################
# Sets the IPAddress and gateway for the VMs #
##############################################

Write-Host "Setting gateway for IPAddress"
# This should be run last after a vagrant reload. vagrant reload wipes this setting for some reason
netsh interface ipv4 set address name="$NetbiosName" static ([IPAddress]$IPAddress) 255.255.255.0 ([IPAddress]$GatewayIP.Trim())
Write-Host "Completed setting gateway for IPAddress"

################################################################################
# Disables The Firewall For Easy access (This would not be done in a prod env) #
################################################################################

Write-Host "Disabling windows wirewall"
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
Write-Host "Completed Disabling windows wirewall"

ipconfig.exe /registerdns

#Add flat domain name DNS record to speed up start of gpsvc in 2016
dnscmd localhost /recordadd $env:USERDNSDOMAIN $env:USERDOMAIN A ([IPAddress]$IPAddress)

### Force Sync
ipconfig.exe -flushdns

if (-not -(Test-Path -Path C:\DeployDebug)) {
    New-Item C:\DeployDebug -Force -ItemType Directory | Out-Null
}

Write-Verbose -Message 'Getting list of DCs'
$dcs = repadmin.exe /viewlist *
Write-Verbose -Message "List: '$($dcs -join ', ')'"
(Get-Date -Format 'yyyy-MM-dd hh:mm:ss') | Add-Content -Path c:\DeployDebug\DCList.log -Force
$dcs | Add-Content -Path c:\DeployDebug\DCList.log

foreach ($dc in $dcs) {
    if ($dc) {
        $dcName = $dc.Split()[2]
        Write-Verbose -Message "Executing 'repadmin.exe /SyncAll /Ae $dcname'"
        $result = repadmin.exe /SyncAll /Ae $dcName
        (Get-Date -Format 'yyyy-MM-dd hh:mm:ss') | Add-Content -Path "c:\DeployDebug\Syncs-$($dcName).log" -Force
        $result | Add-Content -Path "c:\DeployDebug\Syncs-$($dcName).log"
    }
}
Write-Verbose -Message "Executing 'repadmin.exe /ReplSum'"
$result = repadmin.exe /ReplSum
$result | Add-Content -Path c:\DeployDebug\repadmin.exeResult.log

Restart-Service -Name DNS -WarningAction SilentlyContinue

ipconfig.exe /registerdns

Write-Verbose -Message 'Getting list of DCs'
$dcs = repadmin.exe /viewlist *
Write-Verbose -Message "List: '$($dcs -join ', ')'"
(Get-Date -Format 'yyyy-MM-dd hh:mm:ss') | Add-Content -Path c:\DeployDebug\DCList.log -Force
$dcs | Add-Content -Path c:\DeployDebug\DCList.log
foreach ($dc in $dcs) {
    if ($dc) {
        $dcName = $dc.Split()[2]
        Write-Verbose -Message "Executing 'repadmin.exe /SyncAll /Ae $dcname'"
        $result = repadmin.exe /SyncAll /Ae $dcName
        (Get-Date -Format 'yyyy-MM-dd hh:mm:ss') | Add-Content -Path "c:\DeployDebug\Syncs-$($dcName).log" -Force
        $result | Add-Content -Path "c:\DeployDebug\Syncs-$($dcName).log"
    }
}
Write-Verbose -Message "Executing 'repadmin.exe /ReplSum'"
$result = repadmin.exe /ReplSum
$result | Add-Content -Path c:\DeployDebug\repadmin.exeResult.log

ipconfig.exe /registerdns

Restart-Service -Name DNS -WarningAction SilentlyContinue

### Install Replication Site
if (-not (Get-ADReplicationSite -Filter "Name -eq 'Default-First-Site-Name'")) {
    Write-Host "Creating Default Replication Site"
    New-ADReplicationSite -Name "Default-First-Site-Name"

    $networkInfo = Get-NetworkSummary -IPAddress ([IPAddress]$IPAddress) -SubnetMask 255.255.255.0
    $PSDefaultParameterValues = @{
            '*-AD*:Server' = $env:COMPUTERNAME
        }

    $ctx = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Forest)
    $defaultSite = [System.DirectoryServices.ActiveDirectory.ActiveDirectorySite]::FindByName($ctx, 'Default-First-Site-Name')
    $subnetName = "$($NetworkInfo.Network)/$($NetworkInfo.MaskLength)"

    try
    {
        $subnet = Get-ADReplicationSubnet -Identity $subnetName -Server localhost
    }
    catch { }

    if (-not $subnet) {
        $subnet = New-Object System.DirectoryServices.ActiveDirectory.ActiveDirectorySubnet($ctx, $subnetName)
        $subnet.Site = $defaultSite
        $subnet.Save()
    }
}

Get-PSSession | Where-Object { $_.Name -ne 'WinPSCompatSession' -and $_.State -ne 'Disconnected'} | Remove-PSSession

# Force autologon by domain admin
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name AutoAdminLogon -Value 1 -Type String -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name AutoLogonCount -Value 9999 -Type DWORD -Force

Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name DefaultPassword -Value $plaintextPass -Type String -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name DefaultUserName -Value "$NetbiosName\$vagrantUsername" -Type String -Force

Exit 0