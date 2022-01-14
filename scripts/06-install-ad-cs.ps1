Param(
    $domain,
    $domainNet,
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
        Start-Sleep -Seconds 15
    }
}

$pw = ConvertTo-SecureString "$plaintextPass" -AsPlainText -Force
$ADUserCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "$domainNet\$vagrantUsername",$pw 

$localServerHostname = $env:COMPUTERNAME

$mainScriptSession = New-PSSession -ComputerName $localServerHostname -Credential $ADUserCredential -Authentication Credssp
try { 
    Invoke-Command -Session $mainScriptSession -ArgumentList $localServerHostname, $domain, $domainNet, $pw, $ADUserCredential, $vagrantUsername -ScriptBlock {
        Param(
            $localServerHostname,
            $domain,
            $domainNet,
            $pw,
            $ADUserCredential,
            $vagrantUsername
        )

        Set-ExecutionPolicy Bypass -Scope Process -Force

        $adDomain = Get-ADDomain

        $domainDn = $adDomain.DistinguishedName

        $serverFull = $localServerHostname+'.'+$domain

        # Create inf file
        $caPolicyFileName = "$Env:Windir\CAPolicy.inf"
        if (-not (Test-Path -Path $caPolicyFileName)) {
            Set-Content $caPolicyFileName -Force -Value ';CAPolicy for CA'
            Add-Content $caPolicyFileName -Value '; Please replace sample CPS OID with your own OID'
            Add-Content $caPolicyFileName -Value ''
            Add-Content $caPolicyFileName -Value '[Version]'
            Add-Content $caPolicyFileName -Value "Signature=`"`$Windows NT`$`" "
            Add-Content $caPolicyFileName -Value ''
            Add-Content $caPolicyFileName -Value '[PolicyStatementExtension]'
            Add-Content $caPolicyFileName -Value 'Policies=LegalPolicy'
            Add-Content $caPolicyFileName -Value 'Critical=0'
            Add-Content $caPolicyFileName -Value ''
            Add-Content $caPolicyFileName -Value '[LegalPolicy]'
            Add-Content $caPolicyFileName -Value 'OID=1.3.6.1.4.1.11.21.43'
            Add-Content $caPolicyFileName -Value "Notice=Certification Practice Statement"
            Add-Content $caPolicyFileName -Value "URL=http://$serverFull/cps/cps.html"
            Add-Content $caPolicyFileName -Value ''
            Add-Content $caPolicyFileName -Value '[Certsrv_Server]'
            Add-Content $caPolicyFileName -Value 'ForceUTF8=true'
            Add-Content $caPolicyFileName -Value "RenewalKeyLength=2048"
            Add-Content $caPolicyFileName -Value "RenewalValidityPeriod=Years"
            Add-Content $caPolicyFileName -Value "RenewalValidityPeriodUnits=5"
            Add-Content $caPolicyFileName -Value "CRLPeriod=Years"
            Add-Content $caPolicyFileName -Value "CRLPeriodUnits=5"
            Add-Content $caPolicyFileName -Value "CRLDeltaPeriod=Years"
            Add-Content $caPolicyFileName -Value "CRLDeltaPeriodUnits=5"
            Add-Content $caPolicyFileName -Value 'EnableKeyCounting=0'
            Add-Content $caPolicyFileName -Value 'LoadDefaultTemplates=1'
            Add-Content $caPolicyFileName -Value 'AlternateSignatureAlgorithm=1'
            Add-Content $caPolicyFileName -Value ''
            Add-Content $caPolicyFileName -Value '[Extensions]'
            Add-Content $caPolicyFileName -Value ';Remove CA Version Index'
            Add-Content $caPolicyFileName -Value '1.3.6.1.4.1.311.21.1='
            Add-Content $caPolicyFileName -Value ';Remove CA Hash of previous CA Certificates'
            Add-Content $caPolicyFileName -Value '1.3.6.1.4.1.311.21.2='
            Add-Content $caPolicyFileName -Value ';Remove V1 Certificate Template Information'
            Add-Content $caPolicyFileName -Value '1.3.6.1.4.1.311.20.2='
            Add-Content $caPolicyFileName -Value ';Remove CA of V2 Certificate Template Information'
            Add-Content $caPolicyFileName -Value '1.3.6.1.4.1.311.21.7='
            Add-Content $caPolicyFileName -Value ';Key Usage Attribute set to critical'
            Add-Content $caPolicyFileName -Value '2.5.29.15=AwIBBg=='
            Add-Content $caPolicyFileName -Value 'Critical=2.5.29.15'

        }
        New-Item -Path C:\vagrant\certs\CertData -Type Directory -Force #Should exist already but just in case
        New-Item -Path C:\Windows\System32\CertSrv\CertEnroll -Type SymbolicLink -Value C:\vagrant\certs\CertData -Force

        Install-WindowsFeature ADCS-Cert-Authority, ADCS-Web-Enrollment -IncludeManagementTools

        Write-Host "About to install ADCS CA"
        Install-AdcsCertificationAuthority `
            -CAType EnterpriseRootCA `
            -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
            -KeyLength 2048 `
            -HashAlgorithmName SHA1 `
            -ValidityPeriod Years `
            -ValidityPeriodUnits 5 `
            -CACommonName $domainNet-ROOT-CA `
            -CADistinguishedNameSuffix $domainDn `
            -OverwriteExistingKey `
            -OverwriteExistingDatabase `
            -Credential $ADUserCredential `
            -Force

        Install-ADCSWebEnrollment -Confirm:$False -Force

        Add-WindowsFeature -Name 'Web-Server' -IncludeManagementTools

        net localgroup IIS_IUSRS "$domainNet\kb" /Add
        net localgroup IIS_IUSRS "$domainNet\$vagrantUsername" /Add

        #Allow "+" characters in URL for supporting delta CRLs
        Set-WebConfiguration -Filter system.webServer/security/requestFiltering -PSPath 'IIS:\sites\Default Web Site' -Value @{allowDoubleEscaping=$true}

        New-WebVirtualDirectory -Site 'Default Web Site' -Name Aia -PhysicalPath 'C:\Windows\System32\CertSrv\CertEnroll' | Out-Null
        New-WebVirtualDirectory -Site 'Default Web Site' -Name Cdp -PhysicalPath 'C:\Windows\System32\CertSrv\CertEnroll' | Out-Null

        Write-Host "Completed installing ADCS CA. About to set certutil values."

        #Declare config NC
        certutil -setreg CA\DSConfigDN "CN=Configuration,$domainDn"

        #Apply the required CDP Extension URLs
        certutil -setreg CA\CRLPublicationURLs "1:$($Env:WinDir)\system32\CertSrv\CertEnroll\%3%8%9.crl\n11:ldap:///CN=%7%8,CN=%2,CN=CDP,CN=Public Key Services,CN=Services,%6%10\n2:http://$serverFull/cdp/%3%8%9.crl\n1:http://$serverFull/cdp/%3%8%9.crl"

        #Apply the required AIA Extension URLs
        certutil -setreg CA\CACertPublicationURLs "1:$($Env:WinDir)\system32\CertSrv\CertEnroll\%1_%3%4.crt\n3:ldap:///CN=%7,CN=AIA,CN=Public Key Services,CN=Services,%6%11\n2:http://$serverFull/aia/%1_%3%4.crt\n1:http://$serverFull/aia/%3%8%9.crl"


        #Define default maximum certificate lifetime for issued certificates
        certutil -setreg CA\ValidityPeriodUnits 5
        certutil -setreg CA\ValidityPeriod "Years"

        #Define CRL Publication Intervals
        certutil -setreg CA\CRLPeriodUnits 6
        certutil -setreg CA\CRLPeriod "Days"

        #Define CRL Overlap
        certutil -setreg CA\CRLOverlapUnits 3
        certutil -setreg CA\CRLOverlapPeriod "Days"

        #Define Delta CRL
        certutil -setreg CA\CRLDeltaPeriodUnits 0
        certutil -setreg CA\CRLDeltaPeriod "Hours"

        #Enable Auditing Logging
        certutil -setreg CA\Auditfilter 0x7F

        #Enable Auditing Logging
        certutil -setreg ca\forceteletex +0x20

        #Force digital signature removal in KU for cert issuance (see also kb888180)
        certutil -setreg policy\EditFlags -EDITF_ADDOLDKEYUSAGE

        #Enable SAN
        certutil -setreg policy\EditFlags +EDITF_ATTRIBUTESUBJECTALTNAME2

        #Configure policy module to automatically issue certificates when requested
        certutil -setreg ca\PolicyModules\CertificateAuthority_MicrosoftDefault.Policy\RequestDisposition 1

        Write-Host "Completed setting certutil values."
        ## Restart the CA Service & Publish a New CRL
        Write-Host "Restarting crtService"
        Restart-Service certsvc
        do {
            Start-Sleep -Seconds 5
        } until ((Get-Service -Name 'CertSvc').Status -eq 'Running')
        do {
            $result = Invoke-Expression -Command "certutil -pingadmin .\$domainNet-ROOT-CA"
            if (!($result | Where-Object { $_ -like '*interface is alive*' })) {
                Write-Verbose -Message "Admin interface not ready"
                Start-Sleep -Seconds 10
            }
        } until ($result | Where-Object { $_ -like '*interface is alive*' }) 

        Start-Sleep -Seconds 2

        certutil -crl
        $totalretries = 12
        $retries = 0
        do {
            Start-Sleep -Seconds 5
            $retries++
        } until ((Get-ChildItem "$env:systemroot\system32\CertSrv\CertEnroll\*.crl") -or ($retries -ge $totalretries))
        Write-Host "crtService has completed restarting"

        ## Export Root Cert
        New-Item -Path C:\vagrant\certs\caCerts -Type Directory -Force
        Copy-Item C:\Windows\System32\CertSrv\CertEnroll\*.crt C:\vagrant\certs\caCerts\

        #publish locally first 
        Write-Host "publishing local cert"
        Copy-Item C:\vagrant\certs\caCerts\*.crt C:\Windows\

        foreach ($certfile in (Get-ChildItem -Path 'C:\Windows\*.crt')) {
            if (((Get-PfxCertificate $($certfile.FullName)).Subject) -like '*root*') {
                $dsPublishStoreName = 'RootCA'
                $readStoreName = 'Root'
            }

            if (-not (Get-ChildItem "Cert:\LocalMachine\$readStoreName" | Where-Object { $_.ThumbPrint -eq (Get-PfxCertificate $($certfile.FullName)).ThumbPrint })) {
                $result = Invoke-Expression -Command "certutil -f -dspublish c:\Windows\$($certfile.BaseName).crt $dsPublishStoreName"

                if ($result | Where-Object { $_ -like '*Certificate added to DS store*' }) {
                    Write-Host "  Certificate ($((Get-PfxCertificate $certfile.FullName).Subject)) added to DS store on $(hostname)"
                } elseif ($result | Where-Object { $_ -like '*Certificate already in DS store*' }) {
                    Write-Host "  Certificate ($((Get-PfxCertificate $certfile.FullName).Subject)) is already in DS store on $(hostname)"
                } else {
                    Write-Host "Certificate ($((Get-PfxCertificate $certfile.FullName).Subject)) was not added to DS store on $(hostname)"
                }
            } else {
                Write-Host "  Certificate ($((Get-PfxCertificate $certfile.FullName).Subject)) is already in DS store on $(hostname)"
            }
        }

        gpupdate /force
        Write-Host "done publishing local cert. now enabling domain auth"
        ###Enabling Computer Auto Enrollment

        #Configuring permissions for workstation authentication template for root ca computer on domain controller
        $domainName = ([adsi]'LDAP://RootDSE').DefaultNamingContext

        dsacls "CN=Workstation,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$domainName" /G 'Domain Computers:GR'
        dsacls "CN=Workstation,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$domainName" /G 'Domain Computers:CA;Enroll'
        dsacls "CN=Workstation,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$domainName" /G 'Domain Computers:CA;AutoEnrollment'

        certutil -SetCAtemplates +Workstation
        Write-Host "Done enabling domain auth. now enabling gpo auto enrollment"

        #Enabling gpo Auto Enrollment
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

        Write-Host "Done with local gpo enrollment"

        gpupdate.exe /force

    }
} catch { 
    $_
    write-host "found error"
} 

Exit 0