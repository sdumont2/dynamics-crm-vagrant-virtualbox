Param(
    $Netbios,
    $DCIPAddress,
    $Domain,
    $DCComputerName,
    $vagrantUsername,
    $plaintextPass
)
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }


Set-StrictMode -Version Latest 
Set-ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = "Stop"

Import-Module ServerManager
Install-WindowsFeature RSAT-AD-PowerShell -IncludeAllSubFeature -IncludeManagementTools
Install-WindowsFeature RSAT-AD-Tools -IncludeAllSubFeature -IncludeManagementTools

$env:ADPS_LoadDefaultDrive = 0
Import-Module -Name ActiveDirectory

Write-Host "Setting DNS server to $DCIPAddress..."
Set-DnsClientServerAddress -InterfaceIndex ((Get-NetIPAddress).InterfaceIndex) -ServerAddresses $DCIPAddress

Set-DnsClientGlobalSetting -SuffixSearchList $Domain 

Start-Sleep -Seconds 15

Write-Host "Joining domain..."
$Password = ConvertTo-SecureString "$plaintextPass" -AsPlainText -Force
$Username = "$Netbios\$vagrantUsername" 
Write-Host $Username
$Credential = New-Object PSCredential($Username, $Password)
Add-Computer -DomainName $Domain -Credential $Credential -Verbose -Force

# Force autologon by domain admin
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name AutoAdminLogon -Value 1 -Type String -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name AutoLogonCount -Value 9999 -Type DWORD -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name DefaultDomainName -Value $Domain -Type String -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name DefaultPassword -Value $plaintextPass -Type String -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name DefaultUserName -Value $Username -Type String -Force

Exit 0