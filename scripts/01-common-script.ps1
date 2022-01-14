Param(
    [String]$IPAddress,
    [String]$GatewayIP,
    [String]$ContosoIPAddressPattern,
    [String]$NetbiosName
)

#################################
# Set Time Zone For Consistency #
#################################

Write-Host "Setting time zone"
Set-StrictMode -Version Latest 
Set-TimeZone -Id "Eastern Standard Time"
Write-Host "Completed Setting time zone"


########################
# Install Sysinternals #
########################

Write-Host "Installing Sysinternals"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$internalsExist = test-path C:\Sysinternals
if ($internalsExist -eq $false) {
    [System.IO.Compression.ZipFile]::ExtractToDirectory("c:\Vagrant\install\SysinternalsSuite.zip", "c:\Sysinternals")
}
Write-Host "Completed Installing Sysinternals"


###################
# Install BG Info #
###################

Write-Host "Installing BG Info"
if (!(Test-Path 'c:\Sysinternals\bginfo.exe')) {
  (New-Object Net.WebClient).DownloadFile('http://live.sysinternals.com/bginfo.exe', 'c:\Sysinternals\bginfo.exe')
}
$vbsScript = @'
WScript.Sleep 15000
Dim objShell
Set objShell = WScript.CreateObject( "WScript.Shell" )
objShell.Run("""c:\Sysinternals\bginfo.exe"" /accepteula ""c:\Sysinternals\bginfo.bgi"" /silent /timer:0")
'@

$vbsScript | Out-File 'c:\Sysinternals\bginfo.vbs'

Copy-Item "C:\vagrant\install\bginfo.bgi" 'c:\Sysinternals\bginfo.bgi'

Set-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run -Name bginfo -Value 'wscript "c:\Sysinternals\bginfo.vbs"'
Write-Host "Completed Installing BG Info"

############################################
# Allows remoting from these shell scripts #
############################################

if ((Get-Service -Name WinRM).Status -ne 'Running') {
    Write-Host 'Starting the WinRM service. This is required in order to read the WinRM configuration...' -NoNewLine
    Start-Service -Name WinRM
    Start-Sleep -Seconds 2
    Write-Host "done"
}

if ((Get-Service -Name smphost).StartType -eq 'Disabled') {
    Write-Host "The StartupType of the service 'smphost' is set to disabled. Setting it to 'manual'. This is required in order to read use the cmdlets in the 'Storage' module..." -NoNewLine
    Set-Service -Name smphost -StartupType Manual
    Write-Host "done"
}

Write-Host "Enabling CredSSP, for powershell scripts remoting"
# force English language output for Get-WSManCredSSP call
Enable-PSRemoting -Force
Enable-WSManCredSSP -Role Client -DelegateComputer * -Force
Enable-WSManCredSSP -Role Server -Force 

Start-Sleep -Seconds 3

$trustedHostsList = @((Get-Item -Path Microsoft.WSMan.Management\WSMan::localhost\Client\TrustedHosts).Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } )

if (-not ($trustedHostsList -contains '*')) {
    Set-Item -Path Microsoft.WSMan.Management\WSMan::localhost\Client\TrustedHosts -Value '*' -Force | Out-Null
    Write-Host "'*' added to TrustedHosts"
}
Import-Module C:\vagrant\scripts\05a-adcs-helper.psm1
. C:\vagrant\scripts\05a-adcs-helper.psm1

Start-Sleep -Seconds 3

try{
$value = [GPO.Helper]::GetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentials', '1')
if ($value -ne '*' -and $value -ne 'WSMAN/*') {
    Write-Host 'Configuring the local policy for allowing credentials to be delegated to all machines (*). You can find the modified policy using gpedit.msc by navigating to: Computer Configuration -> Administrative Templates -> System -> Credentials Delegation -> Allow Delegating Fresh Credentials'
    [GPO.Helper]::SetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation', 'AllowFreshCredentials', 1) | Out-Null
    [GPO.Helper]::SetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation', 'ConcatenateDefaults_AllowFresh', 1) | Out-Null
    [GPO.Helper]::SetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentials', '1', 'WSMAN/*') | Out-Null
}
}catch{}

Start-Sleep -Seconds 3
try{
$value = [GPO.Helper]::GetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly', '1')
if ($value -ne '*' -and $value -ne 'WSMAN/*') {
    Write-Host 'Configuring the local policy for allowing credentials to be delegated to all machines (*). You can find the modified policy using gpedit.msc by navigating to: Computer Configuration -> Administrative Templates -> System -> Credentials Delegation -> Allow Delegating Fresh Credentials with NTLM-only server authentication'
    [GPO.Helper]::SetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation', 'AllowFreshCredentialsWhenNTLMOnly', 1) | Out-Null
    [GPO.Helper]::SetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation', 'ConcatenateDefaults_AllowFreshNTLMOnly', 1) | Out-Null
    [GPO.Helper]::SetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly', '1', 'WSMAN/*') | Out-Null
}
}catch{}

Start-Sleep -Seconds 3
try{
$value = [GPO.Helper]::GetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowSavedCredentials', '1')
if ($value -ne '*' -and $value -ne 'TERMSRV/*') {
    Write-Host 'Configuring the local policy for allowing credentials to be delegated to all machines (*). You can find the modified policy using gpedit.msc by navigating to: Computer Configuration -> Administrative Templates -> System -> Credentials Delegation -> Allow Delegating Fresh Credentials' 
    [GPO.Helper]::SetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation', 'AllowSavedCredentials', 1) | Out-Null
    [GPO.Helper]::SetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation', 'ConcatenateDefaults_AllowSaved', 1) | Out-Null
    [GPO.Helper]::SetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowSavedCredentials', '1', 'TERMSRV/*') | Out-Null
}
}catch{}

Start-Sleep -Seconds 3
try{
$value = [GPO.Helper]::GetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowSavedCredentialsWhenNTLMOnly', '1')
if ($value -ne '*' -and $value -ne 'TERMSRV/*') {
    Write-Host 'Configuring the local policy for allowing credentials to be delegated to all machines (*). You can find the modified policy using gpedit.msc by navigating to: Computer Configuration -> Administrative Templates -> System -> Credentials Delegation -> Allow Delegating Fresh Credentials with NTLM-only server authentication'
    [GPO.Helper]::SetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation', 'AllowSavedCredentialsWhenNTLMOnly', 1) | Out-Null
    [GPO.Helper]::SetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation', 'ConcatenateDefaults_AllowSavedNTLMOnly', 1) | Out-Null
    [GPO.Helper]::SetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowSavedCredentialsWhenNTLMOnly', '1', 'TERMSRV/*') | Out-Null
}
}catch{}

Start-Sleep -Seconds 3

$allowEncryptionOracle = 0
try {
    $allowEncryptionOracle = (Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP\Parameters -ErrorAction SilentlyContinue).AllowEncryptionOracle
} catch {}
try{
if ($allowEncryptionOracle -ne 2) {
    Write-Host "Setting registry value 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP\Parameters\AllowEncryptionOracle' to '2'."
    New-Item -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP\Parameters -Force 
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP\Parameters -Name AllowEncryptionOracle -Value 2 -Force
}
}catch{}

Write-Host "Completed Enabling CredSSP, for powershell scripts remoting"


##################################################################
# Rename the network adapter to contoso for easy alias switching #
##################################################################

Write-Host "Setting network adapter alias for easy access"
Get-NetAdapter -InterfaceIndex (Get-NetIPAddress -IPAddress $ContosoIPAddressPattern).InterfaceIndex | Rename-NetAdapter -NewName $NetbiosName
Write-Host "Completed Setting network adapter alias for easy access"


##############################################
# Sets the IPAddress and gateway for the VMs #
##############################################

Write-Host "Setting gateway for IPAddress"
# This should be run last after a vagrant reload. vagrant reload wipes this setting for some reason
netsh interface ipv4 set address name="$NetbiosName" static ([IPAddress]$IPAddress) 255.255.255.0 ([IPAddress]$GatewayIP.Trim())
Write-Host "Completed setting gateway for IPAddress"


######################################################################################
# Disable IPv6 to prevent attempts to use the protocol on the VMs                    #
# https://www.tenforums.com/tutorials/90033-enable-disable-ipv6-windows.html#option6 #
######################################################################################

Write-Host "Disabling IPv6 on network adapters"
Disable-NetAdapterBinding -Name "*" -ComponentID ms_tcpip6
Write-Host "Completed Disabling IPv6 on network adapters"


################################################################################
# Disables The Firewall For Easy access (This would not be done in a prod env) #
################################################################################

Write-Host "Disabling windows wirewall"
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
Write-Host "Completed Disabling windows wirewall"


##################################
# Increases Max TCP Connections  #
##################################

Write-Host "Increasing max TCP Connections"
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name TcpNumConnections -Value 16777214
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name TcpTimedWaitDelay -Value 30
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name MaxFreeTcbs -Value 100000
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name MaxHashTableSize -Value 32768
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name MaxUserPort -Value 65534
Write-Host "Completed Increasing max TCP Connections"

