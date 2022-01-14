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
        Start-Sleep -Seconds 20
    }
}

$pw = ConvertTo-SecureString "$plaintextPass" -AsPlainText -Force
$ADUserCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "$domainNet\$vagrantUsername",$pw 

$mainScriptSession = New-PSSession -ComputerName $env:COMPUTERNAME -Credential $ADUserCredential -Authentication Credssp
try { 
    Invoke-Command -Session $mainScriptSession -ScriptBlock {

        Set-ExecutionPolicy Bypass -Scope Process -Force

        #Disables The Firewall
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

        Write-Host "Waiting for adfs to become reachable."
        while ($true) {
            try {
                Get-AdfsProperties | Out-Null
                break
            } catch {
                Start-Sleep -Seconds 20
            }
        }

        Import-Module ActiveDirectory

        $TmpCertificateDirectory = "C:\vagrant\tmp"

        Import-Module ADFS

        $TokenSigningCertificatePath = "$TmpCertificateDirectory\adfs_token_signing.cer"
        Write-Host "Exporting ADFS Token Signing Certificate  to '$TokenSigningCertificatePath'..."
        $Cert=Get-AdfsCertificate -CertificateType Token-Signing
        $CertBytes=$Cert[0].Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
        [System.IO.File]::WriteAllBytes($TokenSigningCertificatePath, $certBytes)

        # Configure WIA for only proper browsers
        #Set-AdfsProperties -WIASupportedUserAgents @("MSIE 6.0", "MSIE 7.0; Windows NT", "MSIE 8.0", "MSIE 9.0", "MSIE 10.0; Windows NT 6", "Windows NT 6.3; Trident/7.0", "Windows NT 6.3; Win64; x64; Trident/7.0", "Windows NT 6.3; WOW64; Trident/7.0", "Windows NT 6.2; Trident/7.0", "Windows NT 6.2; Win64; x64; Trident/7.0", "Windows NT 6.2; WOW64; Trident/7.0", "Windows NT 6.1; Trident/7.0", "Windows NT 6.1; Win64; x64; Trident/7.0", "Windows NT 6.1; WOW64; Trident/7.0","Windows NT 10.0; WOW64; Trident/7.0", "MSIPC", "Windows Rights Management Client", "=~Windows\s*NT.*Edg.*")
        # Lets forms be the fallback
        #Set-AdfsGlobalAuthenticationPolicy -WindowsIntegratedFallbackEnabled $true

        #Allows Chrome for windows
        #Set-AdfsProperties -WIASupportedUserAgents ((Get-ADFSProperties | Select -ExpandProperty WIASupportedUserAgents) + "Mozilla/5.0 (Windows NT)")
        #Allows chrome for mac OS too 
        #Set-AdfsProperties -WIASupportedUserAgents ((Get-ADFSProperties | Select -ExpandProperty WIASupportedUserAgents) + "Mozilla/5.0 (Macintosh; Intel Mac OS X)")

        #Makes identifier the same as provider
        #$adfsProperties = Get-AdfsProperties
        #Set-AdfsProperties -Identifier $adfsProperties.IdTokenIssuer
        net stop adfssrv 
        net start adfssrv
    }
} catch { 
    $_
    write-host "found error"
} 

Exit 0