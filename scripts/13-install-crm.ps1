Param(
    $domain,
    $domainNet,
    $vagrantUsername,
    $plaintextPass
)
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }

Write-Host "Sleeping for 45 seconds to ensure other services are up"
Start-Sleep -Seconds 45
while ($true) {
    try {
        $env:ADPS_LoadDefaultDrive = 0
        $WarningPreference = 'SilentlyContinue'
        Import-Module -Name ActiveDirectory -ErrorAction Stop
        Get-ADDomain -Server $domain
        break
    } catch {
        $_
        write-host $error[0] 
        Start-Sleep -Seconds 20
    }
}

$pw = ConvertTo-SecureString "$plaintextPass" -AsPlainText -Force
$ADUserCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "$domainNet\$vagrantUsername",$pw 

$currentComputerName = $env:COMPUTERNAME
Set-ExecutionPolicy Bypass -Scope Process -Force

$mainScriptSession = New-PSSession -ComputerName $currentComputerName -Credential $ADUserCredential -Authentication Credssp 
try { 
    Invoke-Command -Session $mainScriptSession -Verbose -ArgumentList $domain, $domainNet, $currentComputerName, $vagrantUsername, $plaintextPass, $ADUserCredential -ScriptBlock {
        Param(
            $domain,
            $domainNet,
            $currentComputerName,
            $vagrantUsername,
            $plaintextPass,
            $ADUserCredential
        )
        Set-ExecutionPolicy Bypass -Scope Process -Force

        # Makes sure SQL Server is up and running
        Get-Service -Name *SQLSERVERAGENT* | Set-Service -StartupType Automatic -Status Running
 
        Write-Host "Starting CRM Install Prep"
        $adDomain = Get-ADDomain -Server $domain 
        $domainDn = $adDomain.DistinguishedName
        $usersAdPath = "CN=Users,$domainDn"

        Add-LocalGroupMember -Group "Performance Monitor Users" -Member "$domainNet\$vagrantUsername", "$domainNet\CRMAsyncService", "$domainNet\CRMAppService"
        Add-LocalGroupMember -SID 'S-1-5-32-559' -Member "$domainNet\CRMAsyncService", "$domainNet\CRMAppService"

        Remove-Item -Path C:\crmsetup\logcrm.log -Force -ErrorAction Ignore
        C:\vagrant\scripts\12a-configure-crm-xml.ps1 $currentComputerName $domainNet $domainDn 'zaq1@WSX'

        Import-Module C:\vagrant\scripts\05a-adcs-helper.psm1
        . C:\vagrant\scripts\05a-adcs-helper.psm1

        $userGroup = "Everyone"

        # Create the rule in anticipation
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($userGroup, 'FullControl', 'Allow')

        $acl = (Get-Item C:\crmsetup).GetAccessControl('Access')

        $hasPermissionsAlready = ($acl.Access | where {$_.IdentityReference.Value.Contains($userGroup.ToUpperInvariant()) -and $_.FileSystemRights -eq [System.Security.AccessControl.FileSystemRights]::FullControl}).Count -eq 1
 
        if ($hasPermissionsAlready){
            Write-Host "C:\crmsetup already has the FullControl permissions to group $userGroup." -ForegroundColor Green
        } else {
            $acl.AddAccessRule($rule)
            Set-Acl -Path C:\crmsetup -AclObject $acl
        }

        Start-Sleep -Seconds 15

        try { 

            $currentTime = Get-Date
            Write-Host "Installation started: $currentTime"
            Start-Sleep -Seconds 15

            # This function is from the helper script
            Install-SoftwarePackage -Path "C:\crmsetup\SetupServer.exe" -CommandLine "/config C:\crmsetup\crmconfig.xml /log C:\crmsetup\logcrm.log /Q /InstallAlways" -AsScheduledJob:$True -UseShellExecute:$True -ExpectedReturnCodes 0,3010 -Credential $ADUserCredential
        }catch { 
            $_
            write-host "found error" 
            write-host $error[0] 
        }
    }
} catch { 
    $_
    write-host "found error"
} 

Start-Sleep -Seconds 30

Exit 0

