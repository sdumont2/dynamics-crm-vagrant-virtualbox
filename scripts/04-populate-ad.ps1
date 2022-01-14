Param (
    $crmHostName,
    [String]$netAddressSpace,
    $vagrantUsername,
    $plaintextPass
)
############################################################
# Populate the ActiveDirectory with Users and setting SPNs #
############################################################

Start-Sleep -Seconds 15
while ($true) {
    if ((Get-Service -Name ADWS -ErrorAction SilentlyContinue).Status -eq 'Running') {
        try {
            $env:ADPS_LoadDefaultDrive = 0
            $WarningPreference = 'SilentlyContinue'
            Import-Module -Name ActiveDirectory -ErrorAction Stop
            Get-ADDomain | Out-Null
            break
        } catch {
            Start-Sleep -Seconds 20
        }
    } else {
        Start-Sleep -Seconds 20
    }
}

#Adding kb and vagrant users to proper AD groups
Set-ExecutionPolicy Bypass -Scope Process
Set-StrictMode -Version Latest 

$PSDefaultParameterValues = @{
                '*-AD*:Server' = $env:COMPUTERNAME
            }

## Make sure install Users is admin as well
$user = Get-ADUser -Identity ([System.Security.Principal.WindowsIdentity]::GetCurrent().User) -Server localhost

Add-ADGroupMember -Identity 'Domain Admins' -Members $user -Server localhost
Add-ADGroupMember -Identity 'Enterprise Admins' -Members $user -Server localhost
Add-ADGroupMember -Identity 'Schema Admins' -Members $user -Server localhost
##

$adDomain = Get-ADDomain
$netbiosName = $adDomain.NetBIOSName
$domain = $adDomain.DNSRoot
$domainDn = $adDomain.DistinguishedName
$usersAdPath = "CN=Users,$domainDn"
$password = ConvertTo-SecureString -AsPlainText "$plaintextPass" -Force
$name = 'kb'

## Create CRM Users and groups
New-ADOrganizationalUnit -Name "CRM" -Path $domainDn
$ouPath = "OU=CRM,$domainDn"

$svcActPw = ConvertTo-SecureString -AsPlainText 'zaq1@WSX' -Force
[hashtable] $crmServiceAccount = @{Name="CRMAppService";AccountPassword=$svcActPw;Enabled=$True;ErrorAction='Stop'}
[hashtable] $sandboxServiceAccount = @{Name="CRMSandboxService";AccountPassword=$svcActPw;Enabled=$True;ErrorAction='Stop'}
[hashtable] $deploymentServiceAccount = @{Name="CRMDeploymentService";AccountPassword=$svcActPw;Enabled=$True;ErrorAction='Stop'}
[hashtable] $asyncServiceAccount = @{Name="CRMAsyncService";AccountPassword=$svcActPw;Enabled=$True;ErrorAction='Stop'}
[hashtable] $vssServiceAccount = @{Name="CRMVSSWriterService";AccountPassword=$svcActPw;Enabled=$True;ErrorAction='Stop'}
[hashtable] $monitoringServiceAccount = @{Name="CRMMonitoringService";AccountPassword=$svcActPw;Enabled=$True;ErrorAction='Stop'}
[hashtable[]] $users = @($crmServiceAccount,$sandboxServiceAccount,$deploymentServiceAccount,$asyncServiceAccount,$vssServiceAccount,$monitoringServiceAccount)

foreach ($newusers in $users) {
    try {
        New-ADUser @newusers
    } catch {}
}

[hashtable] $privGroup = @{Name="PrivUserGroup";GroupScope="DomainLocal";GroupCategory="Security";Path=$ouPath;ErrorAction='Stop'}
[hashtable] $sqlGroup = @{Name="SQLAccessGroup";GroupScope="DomainLocal";GroupCategory="Security";Path=$ouPath;ErrorAction='Stop'}
[hashtable] $reportGroup = @{Name="ReportingGroup";GroupScope="DomainLocal";GroupCategory="Security";Path=$ouPath;ErrorAction='Stop'}
[hashtable] $privRepGroup = @{Name="PrivReportingGroup";GroupScope="DomainLocal";GroupCategory="Security";Path=$ouPath;ErrorAction='Stop'}

[hashtable[]] $groups = @($privGroup,$sqlGroup,$reportGroup,$privRepGroup)

foreach ($newgroups in $groups) {
    try {
        New-ADGroup @newgroups
    } catch {}
}

$privGroupDN = "CN=PrivUserGroup,$ouPath"
$sqlGroupDN = "CN=SQLAccessGroup,$ouPath"
$reportGroupDN = "CN=ReportingGroup,$ouPath"
$privRepGroupDN = "CN=PrivReportingGroup,$ouPath"

$memberships = @{
    $privGroupDN = @(
        "$netbiosName\CRMAppService"
        "$netbiosName\CRMDeploymentService"
        "$netbiosName\CRMAsyncService"
        "$netbiosName\CRMVSSWriterService"
        "$netbiosName\$vagrantUsername"
        )
    $sqlGroupDN = @(
        "$netbiosName\CRMAppService"
        "$netbiosName\CRMDeploymentService"
        "$netbiosName\CRMAsyncService"
        "$netbiosName\CRMVSSWriterService"
        "$netbiosName\$vagrantUsername"
        )
    $reportGroupDN = @(
        "$netbiosName\$vagrantUsername"
        )
    $privRepGroupDN = @(
        "$netbiosName\$vagrantUsername"
        )
}

foreach ($newmembership in $memberships.GetEnumerator()) {
    try {
        if (-not $newmembership.Value) { continue }
        Add-ADGroupMember -Identity $newmembership.Key -Members ($newmembership.Value -replace '.*\\' | Where-Object { $_ })
    } catch {}
}

# Create  test login user
New-ADUser `
    -Path $usersAdPath `
    -Name 'testUser' `
    -UserPrincipalName "testUser@$domain" `
    -SamAccountName 'testUser' `
    -GivenName 'TestGivenName' `
    -Surname 'TestSurname' `
    -DisplayName 'Test User' `
    -AccountPassword $svcActPw `
    -Enabled $True `
    -PasswordNeverExpires $true

# Now set user groups for service users
New-ADUser `
    -Path $usersAdPath `
    -Name $name `
    -UserPrincipalName "$name@$domain" `
    -SamAccountName $name `
    -EmailAddress "$name@$domain" `
    -GivenName 'kb' `
    -Surname 'Doe' `
    -DisplayName 'kb' `
    -AccountPassword $svcActPw `
    -Enabled $true `
    -TrustedForDelegation $true `
    -PasswordNeverExpires $true 
# add user to the Domain Admins group.
Add-ADGroupMember `
    -Identity 'Domain Admins' `
    -Members "CN=$name,$usersAdPath"
Add-ADGroupMember `
    -Identity 'Enterprise Admins' `
    -Members "CN=$name,$usersAdPath"
Add-ADGroupMember `
    -Identity 'Schema Admins' `
    -Members "CN=$name,$usersAdPath"
Add-ADGroupMember `
    -Identity 'Administrators' `
    -Members "CN=$name,$usersAdPath"

#Adding Vagrant User Too
Add-ADGroupMember `
    -Identity 'Domain Admins' `
    -Members "CN=$vagrantUsername,$usersAdPath"
Add-ADGroupMember `
    -Identity 'Enterprise Admins' `
    -Members "CN=$vagrantUsername,$usersAdPath"
Add-ADGroupMember `
    -Identity 'Schema Admins' `
    -Members "CN=$vagrantUsername,$usersAdPath"

Add-ADGroupMember `
    -Identity 'Performance Monitor Users' `
    -Members "CN=$vagrantUsername,$usersAdPath"
Add-ADGroupMember `
    -Identity 'Performance Log Users' `
    -Members "CN=$vagrantUsername,$usersAdPath"

Get-ADUser $vagrantUsername | Set-ADUser -TrustedForDelegation $True

# Create ADFS Service User
New-ADUser -Name "AdfsService" -AccountPassword $svcActPw -Enabled $True -PasswordNeverExpires $true

setspn -a MSCRMAsyncService/$crmHostName $netbiosName\$vagrantUsername

try {
    # Try to create reverse lookup zones
    $pw = ConvertTo-SecureString "$plaintextPass" -AsPlainText -Force
    $ADUserCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "$domainNet\$vagrantUsername",$pw 

    $mainScriptSession = New-PSSession -ComputerName $env:COMPUTERNAME -Credential $ADUserCredential -Authentication Credssp
    try { 
        Invoke-Command -Session $mainScriptSession -ArgumentList $netAddressSpace -ScriptBlock {
            Param (
                $netAddressSpace
            )
            Set-ExecutionPolicy Bypass -Scope Process -Force

            $zoneName = "$($netAddressSpace.split('.')[2]).$($netAddressSpace.split('.')[1]).$($netAddressSpace.split('.')[0]).in-addr.arpa"
                dnscmd . /ZoneAdd "$zoneName" /DsPrimary /DP /forest
                dnscmd . /Config "$zoneName" /AllowUpdate 2
                ipconfig.exe -registerdns
        }
    } catch { 
        $_
        write-host "found error"
    }
} catch {}

Exit 0

