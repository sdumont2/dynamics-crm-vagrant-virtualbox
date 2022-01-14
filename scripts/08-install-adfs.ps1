Param(
    $domain,
    $domainNet,
    $vagrantUsername,
    $plaintextPass
)

Start-Sleep -Seconds 15
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

$localServerHostname = $env:COMPUTERNAME

$mainScriptSession = New-PSSession -ComputerName $localServerHostname -Credential $ADUserCredential -Authentication Credssp
try { 
    Invoke-Command -Session $mainScriptSession -ArgumentList $localServerHostname, $domainNet, $domain, $pw, $ADUserCredential, $plaintextPass -ScriptBlock {
        Param(
            $localServerHostname,
            $domainNet,
            $domain,
            $pw,
            $ADUserCredential,
            $plaintextPass
        )
        Set-ExecutionPolicy Bypass -Scope Process -Force

        Install-WindowsFeature Windows-Identity-Foundation -IncludeManagementTools


        $ADFSDisplayName         = "AdfsContoso"
        $ADFSServiceName         = "AdfsService"

        $ADFSCertSub             = "CN=adfs.$domain"
        $ADFSCertSan             = "adfs.$domain", "enterpriseregistration.$domain"
        $ADFSFlatName            = "adfs"
        $ADFSFullName            = "adfs.$domain"

        $CertificateDirectory    = "C:\vagrant\certs"

        $serverFull = $localServerHostname + '.' + $domain

        Write-Host "ensuring the certificate service is started"
        Start-Service -Name CertSvc -ErrorAction SilentlyContinue
        $templates = certutil.exe -CATemplates
        $caName = ((certutil -config $localServerHostname -ping)[1] -split '"')[1]
        # ends up being something like ca1.contoso.com\contoso-ROOT-CA
        $caPath = $serverFull + '\' + $caName

        Write-Host "Creating template for ADFS SSL"
        Import-Module C:\vagrant\scripts\05a-adcs-helper.psm1
        . C:\vagrant\scripts\05a-adcs-helper.psm1


        New-CATemplate -TemplateName AdfsSsl -DisplayName 'ADFS SSL' -SourceTemplateName WebServer -ApplicationPolicy 'Server Authentication' `
                    -EnrollmentFlags Autoenrollment -PrivateKeyFlags AllowKeyExport -Version 2 -ErrorAction Stop

        Add-CATemplateStandardPermission -TemplateName AdfsSsl -SamAccountName 'Domain Computers'
         
        Write-Host "Forcing AD Replication and Sync"  
        #Force AD Sync/replications
        Add-KdsRootKey -EffectiveTime (Get-Date).AddHours(-10)
        $VerbosePreference = $using:VerbosePreference

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
        Write-Host "AD Replication and Sync Complete" 

        Write-Host "publishing the cert"
        #puglish the cert
        Publish-CaTemplate -TemplateName AdfsSsl 

        $cert = Request-Certificate -Subject $ADFSCertSub -SAN $ADFSCertSan -TemplateName AdfsSsl -OnlineCA $caPath 
        $certThumbprint = $cert.Thumbprint

        $certificate = Get-Item -Path "Cert:\LocalMachine\My\$certThumbprint"

        Set-StrictMode -Version Latest 

        # ADFS Install
        Install-WindowsFeature -Name ADFS-Federation -IncludeManagementTools

        $adfsServicePw = ConvertTo-SecureString 'zaq1@WSX' -AsPlainText -Force
        $adfsServiceCred = New-Object System.Management.Automation.PSCredential -ArgumentList "$domainNet\$ADFSServiceName",$adfsServicePw

        #Sleep for a few seconds to let account creation to finish up
        Start-Sleep -Seconds 5

        Install-AdfsFarm `
            -CertificateThumbprint $certificate.Thumbprint `
            -FederationServiceDisplayName $ADFSDisplayName `
            -FederationServiceName $certificate.SubjectName.Name.Substring(3) `
            -ServiceAccountCredential $adfsServiceCred 

        # This gives an "error" about the service not existing
        # but without it the ADFS service doesn't actually start up, so idk
        sc.exe triggerinfo kdssvc start/networkon

    }
} catch { 
    $_
    write-host "found error"
} 

Exit 0