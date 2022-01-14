Param(
    $domain,
    $domainNet,
    $dcHostname,
    [String]$dcIpAddress,
    $vagrantUsername,
    $plaintextPass
)

Start-Sleep -Seconds 5
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

Set-ExecutionPolicy Bypass -Scope Process -Force

$Username = "$domainNet\$vagrantUsername"
$localGroup = ([ADSI]'WinNT://./Administrators,group')
$localGroup.psbase.Invoke('Add', ([ADSI]"WinNT://$($Username.replace('\', '/'))").path)
Write-Host -Message "Check 2c -create credential of ""$Username"" and ""vagrant"""

Write-Host ([System.Security.Principal.WindowsIdentity]::GetCurrent().User)
Write-Host ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)

$pw = ConvertTo-SecureString "$plaintextPass" -AsPlainText -Force
$ADUserCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $Username,$pw
Write-Host "The username var is $Username"
$mainScriptSession = New-PSSession -ComputerName $env:COMPUTERNAME -Credential $ADUserCredential -Authentication Credssp
try { 
    Invoke-Command -Session $mainScriptSession -ArgumentList $domain, $domainNet, $dcHostname, $dcIpAddress, $Username, $pw, $ADUserCredential -ScriptBlock {
        Param(
            $domain,
            $domainNet,
            $dcHostname,
            $dcIpAddress,
            $Username,
            $pw,
            $ADUserCredential
        )

        Set-ExecutionPolicy Bypass -Scope Process -Force
        Write-Host "Now the Username var is $Username"
        Write-Host ([System.Security.Principal.WindowsIdentity]::GetCurrent().User)
        Write-Host ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
        Add-LocalGroupMember -Group "Administrators" -Member ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)

        Import-Module C:\vagrant\scripts\05a-adcs-helper.psm1
        . C:\vagrant\scripts\05a-adcs-helper.psm1

        Set-Item WSMan:\localhost\Client\TrustedHosts '*' -Force
        Enable-WSManCredSSP -Role Client -DelegateComputer * -Force

        $value = [GPO.Helper]::GetGroupPolicy($true, 'SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentials', '1')
        if ($value -ne '*' -and $value -ne 'WSMAN/*') {
            [GPO.Helper]::SetGroupPolicy($true, 'Software\Policies\Microsoft\Windows\CredentialsDelegation', 'AllowFreshCredentials', 1) | Out-Null
            [GPO.Helper]::SetGroupPolicy($true, 'Software\Policies\Microsoft\Windows\CredentialsDelegation', 'ConcatenateDefaults_AllowFresh', 1) | Out-Null
            [GPO.Helper]::SetGroupPolicy($true, 'Software\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentials', '1', 'WSMAN/*') | Out-Null
        }

        Enable-AutoEnrollment -Computer:$True -UserOrCodeSigning:$True

        netsh.exe interface ipv4 add dnsservers name="$domainNet" address=([IPAddress]$dcIpAddress.Trim()) index=1 validate=yes

        Write-Host "Importing Module Server Manager"
        Import-Module ServerManager
        Write-Host "Installing RSAT AD Powershell"
        Install-WindowsFeature RSAT-AD-PowerShell -IncludeAllSubFeature -IncludeManagementTools

        ipconfig.exe /registerdns

        Write-Host "Forcing AD Replication and Sync"  
        $dcServerFull = $dcHostname + '.' + $domain
        #Force AD Sync/replications
        $s3 = New-PSSession -ComputerName $dcServerFull -Credential $ADUserCredential -Authentication Credssp
        try { 
            Invoke-Command -Session $s3 -ScriptBlock {

                ipconfig.exe -flushdns

                if (-not -(Test-Path -Path C:\DeployDebug)) {
                    New-Item C:\DeployDebug -Force -ItemType Directory | Out-Null
                }

                Write-Host -Message 'Getting list of DCs'
                $dcs = repadmin.exe /viewlist *
                Write-Host -Message "List: '$($dcs -join ', ')'"
                (Get-Date -Format 'yyyy-MM-dd hh:mm:ss') | Add-Content -Path c:\DeployDebug\DCList.log -Force
                $dcs | Add-Content -Path c:\DeployDebug\DCList.log

                foreach ($dc in $dcs) {
                    if ($dc) {
                        $dcName = $dc.Split()[2]
                        Write-Host -Message "Executing 'repadmin.exe /SyncAll /Ae $dcname'"
                        $result = repadmin.exe /SyncAll /Ae $dcName
                        (Get-Date -Format 'yyyy-MM-dd hh:mm:ss') | Add-Content -Path "c:\DeployDebug\Syncs-$($dcName).log" -Force
                        $result | Add-Content -Path "c:\DeployDebug\Syncs-$($dcName).log"
                    }
                }
                Write-Host -Message "Executing 'repadmin.exe /ReplSum'"
                $result = repadmin.exe /ReplSum
                $result | Add-Content -Path c:\DeployDebug\repadmin.exeResult.log

                Restart-Service -Name DNS -WarningAction SilentlyContinue

                ipconfig.exe /registerdns

                Write-Host -Message 'Getting list of DCs'
                $dcs = repadmin.exe /viewlist *
                Write-Host -Message "List: '$($dcs -join ', ')'"
                (Get-Date -Format 'yyyy-MM-dd hh:mm:ss') | Add-Content -Path c:\DeployDebug\DCList.log -Force
                $dcs | Add-Content -Path c:\DeployDebug\DCList.log
                foreach ($dc in $dcs) {
                    if ($dc) {
                        $dcName = $dc.Split()[2]
                        Write-Host -Message "Executing 'repadmin.exe /SyncAll /Ae $dcname'"
                        $result = repadmin.exe /SyncAll /Ae $dcName
                        (Get-Date -Format 'yyyy-MM-dd hh:mm:ss') | Add-Content -Path "c:\DeployDebug\Syncs-$($dcName).log" -Force
                        $result | Add-Content -Path "c:\DeployDebug\Syncs-$($dcName).log"
                    }
                }
                Write-Host -Message "Executing 'repadmin.exe /ReplSum'"
                $result = repadmin.exe /ReplSum
                $result | Add-Content -Path c:\DeployDebug\repadmin.exeResult.log

                ipconfig.exe /registerdns

                Restart-Service -Name DNS -WarningAction SilentlyContinue
            }
        } catch { 
            $_
            write-host "found error"
        }

        gpupdate /force
    }
} catch { 
    $_
    write-host "found error"
} 

Exit 0