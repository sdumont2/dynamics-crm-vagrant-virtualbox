Param(
    $domain,
    $domainNet,
    $caServerHostname,
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

$pw = ConvertTo-SecureString "$plaintextPass" -AsPlainText -Force
$ADUserCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "$domainNet\$vagrantUsername",$pw 

$currentHostname = $env:COMPUTERNAME

$mainScriptSession = New-PSSession -ComputerName $env:COMPUTERNAME -Credential $ADUserCredential -Authentication Credssp
try { 
    Invoke-Command -Session $mainScriptSession -ArgumentList $domain, $domainNet, $caServerHostname, $currentHostname, $pw, $ADUserCredential -ScriptBlock {
        Param(
            $domain,
            $domainNet,
            $caServerHostname,
            $currentHostname,
            $pw,
            $ADUserCredential
        )

        Set-ExecutionPolicy Bypass -Scope Process -Force

        Import-Module ServerManager
        Import-Module WebAdministration

        $caServerFull = $caServerHostname + '.' + $domain

        Write-Host "ensuring the certificate service is started"
        $s1 = New-PSSession -ComputerName $caServerFull -Credential $ADUserCredential -Authentication Credssp
        try { 
            $caPath = Invoke-Command -Session $s1 -ArgumentList $caServerHostname, $caServerFull -ScriptBlock {
                Param(
                    $caServerHostname,
                    $caServerFull
                )
                Start-Service -Name CertSvc -ErrorAction SilentlyContinue
                $templates = certutil.exe -CATemplates
                $caName = ((certutil -config $caServerHostname -ping)[1] -split '"')[1]
                # ends up being something like ca1.contoso.com\contoso-ROOT-CA
                $caPath = $caServerFull + '\' + $caName
                #return it
                $caPath
            }
        } catch { 
            $_
            write-host "found error"
        } 

        $CRMCertSub             = "CN=$currentHostname.$domain"

        Import-Module C:\vagrant\scripts\05a-adcs-helper.psm1
        . C:\vagrant\scripts\05a-adcs-helper.psm1

        $cert = Request-Certificate -Subject $CRMCertSub -TemplateName WebServer -OnlineCA $caPath 
        $certThumbprint = $cert.Thumbprint

        New-WebBinding -Name "Microsoft Dynamics CRM" -IP "*" -Port 443 -Protocol https

        Get-Item -Path "Cert:\LocalMachine\My\$certThumbprint" | New-Item -Path IIS:\SslBindings\0.0.0.0!443

        # A TODO is to uncomment this and add an invoke command to configure all of this via powershell instead of manually, but this is untested as of current

        # Add-PSSnapin Microsoft.Crm.PowerShell

        # # Sets url to the computer hostname and scheme to https and since we're binding to 443 we don't need a port
        # $httpsSettings = Get-CrmSetting -SettingType WebAddressSettings
        # $httpsSettings.DeploymentSdkRootDomain = "$currentHostname.$domain"
        # $httpsSettings.DiscoveryRootDomain = "$currentHostname.$domain"
        # $httpsSettings.SdkRootDomain = "$currentHostname.$domain"
        # $httpsSettings.WebAppRootDomain = "$currentHostname.$domain"
        # $httpsSettings.RootDomainScheme = "https"
        # Set-CrmSetting -Setting $httpsSettings

        # $claimsSettings = Get-CrmSetting -SettingType ClaimsSettings
        # $claimsSettings.Enabled = $True
        # $claimsSettings.EncryptionCertificate = $CRMCertSub
        # $claimsSettings.FederationMetadataUrl = "https://adfs.$domain/FederationMetadata/2007-06/FederationMetadata.xml"
        # Set-CrmSetting -Setting $claimsSettings

        # $oClaimsSettings = Get-CrmSetting -SettingType OAuthClaimsSettings  
        # $oClaimsSettings.Enabled = $true  
        # Set-CrmSetting -Setting $oClaimsSettings

        # Pass Through UPN
        # c:[Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"] => issue(claim = c);

        # Pass Through Primary SID
        # c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/primarysid"] => issue(claim = c);

        # Windows account Name to Name 
        # c:[Type == "* Name"] => issue(Type = "* Name", Issuer = c.Issuer, OriginalIssuer = c.OriginalIssuer, Value = c.Value, ValueType = c.ValueType);

        # Add-AdfsClient -ClientId ce9f9f18-dd0c-473e-b9b2-47812435e20d -Name "Microsoft Dynamics CRM for tablets and phones" -RedirectUri ms-app://s-1-15-2-2572088110-3042588940-2540752943-3284303419-1153817965-2476348055-1136196650/, ms-app://s-1-15-2-1485522525-4007745683-1678507804-3543888355-3439506781-4236676907-2823480090/, ms-app://s-1-15-2-3781685839-595683736-4186486933-3776895550-3781372410-1732083807-672102751/, ms-app://s-1-15-2-3389625500-1882683294-3356428533-41441597-3367762655-213450099-2845559172/, ms-auth-dynamicsxrm://com.microsoft.dynamics,ms-auth-dynamicsxrm://com.microsoft.dynamics.iphone.moca,ms-auth-dynamicsxrm://com.microsoft.dynamics.ipad.good,msauth://code/ms-auth-dynamicsxrm%3A%2F%2Fcom.microsoft.dynamics,msauth://code/ms-auth-dynamicsxrm%3A%2F%2Fcom.microsoft.dynamics.iphone.moca,msauth://code/ms-auth-dynamicsxrm%3A%2F%2Fcom.microsoft.dynamics.ipad.good,msauth://com.microsoft.crm.crmtablet/v%2BXU%2FN%2FCMC1uRVXXA5ol43%2BT75s%3D,msauth://com.microsoft.crm.crmphone/v%2BXU%2FN%2FCMC1uRVXXA5ol43%2BT75s%3D, urn:ietf:wg:oauth:2.0:oob
        # Add-AdfsClient -ClientId 2f29638c-34d4-4cf2-a16a-7caf612cee15 -Name "Dynamics CRM Outlook Client" -RedirectUri app://6BC88131-F2F5-4C86-90E1-3B710C5E308C/
        # Add-AdfsClient -ClientId 4906f920-9f94-4f14-98aa-8456dd5f78a8 -Name "Dynamics 365 Unified Service Desk" -RedirectUri app://41889de4-3fe1-41ab-bcff-d6f0a6900264/
        # Add-AdfsClient -ClientId 2ad88395-b77d-4561-9441-d0e40824f9bc -Name "Dynamics 365 Development Tools" -RedirectUri app://5d3e90d6-aa8e-48a8-8f2c-58b45cc67315/


        # Grant-AdfsApplicationPermission -ClientRoleIdentifier (Get-AdfsClient -Name "Token Broker Client").ClientId -ServerRoleIdentifier https://node.contoso.com/
        # Grant-AdfsApplicationPermission -ClientRoleIdentifier (Get-AdfsClient -Name "Windows Logon Client").ClientId -ServerRoleIdentifier https://node.contoso.com/
        # Grant-AdfsApplicationPermission -ClientRoleIdentifier (Get-AdfsClient -Name "Dynamics 365 Development Tools").ClientId -ServerRoleIdentifier https://node.contoso.com/

        # net stop adfssrv 
        # net start adfssrv


    }
} catch { 
    $_
    write-host "found error"
} 

Exit 0

