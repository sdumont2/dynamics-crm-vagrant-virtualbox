###########################################################################
# Installing Active directory forest and other domain controller services #
###########################################################################
Param(
    $DomainName                    = "contoso.com",
    $DomainNetbiosName             = "contoso",
    $plaintextPass
)
Set-ExecutionPolicy Bypass -Scope Process
Set-StrictMode -Version Latest 
$ErrorActionPreference = "Stop"

([WMIClass]'Win32_NetworkAdapterConfiguration').SetDNSSuffixSearchOrder($DomainName) | Out-Null

Start-Sleep -Seconds (Get-Random -Minimum 15 -Maximum 60)

Write-Host "Installing AD-Domain-Services"
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Install-WindowsFeature -Name DNS -IncludeManagementTools 
Install-WindowsFeature -Name gpmc -IncludeManagementTools 

Import-Module ADDSDeployment

Write-Host "Starting ADDS Forest installation..." 
Install-ADDSForest `
    -DatabasePath "C:\Windows\NTDS" `
    -DomainMode "Win2012R2" `
    -DomainName $DomainName `
    -DomainNetbiosName $DomainNetbiosName `
    -ForestMode "Win2012R2" `
    -InstallDns `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -SafeModeAdministratorPassword (ConvertTo-SecureString 'zaq1@WSX' -AsPlainText -Force) `
    -Force 

Set-ItemProperty -Path Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\NTDS\Parameters -Name 'Repl Perform Initial Synchronizations' -Value 0 -Type DWord

#This allows machines connected to the DNS server to still get resolutions, since these are google's DNS servers
Set-DnsServerForwarder -IPAddress 8.8.8.8,8.8.4.4

Exit 0