Param(
    $domain,
    $domainNet,
    $IPAddress,
    $GatewayIP,
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

$mainScriptSession = New-PSSession -ComputerName $env:COMPUTERNAME -Credential $ADUserCredential -Authentication Credssp
try { 
    Invoke-Command -Session $mainScriptSession -ArgumentList $domain, $domainNet, $pw, $ADUserCredential, $IPAddress, $GatewayIP -ScriptBlock {
        Param(
            $domain,
            $domainNet,
            $pw,
            $ADUserCredential,
            $IPAddress,
            $GatewayIP
        )

        Set-ExecutionPolicy Bypass -Scope Process -Force

        ##########################################################
        # Sets the CA Cert Keys to Read permissions for Everyone #
        ##########################################################

        Write-Host "Setting Local Machine Private Key Permissions to FullControl for Everyone"
        Get-ChildItem Cert:\LocalMachine\My\ | ForEach-Object {
            # Get the Cert info
            $cert = $_
            $certHash = $cert.Thumbprint
            $certSubject = $cert.Subject

            $userGroup = "Everyone"

            # Create the rule in anticipation
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($userGroup, 'FullControl', 'Allow')

            # Get the key name and path
            $keyName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
            $keyPath = "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\"

            $fullPath = $keyPath + $keyName

            $acl = (Get-Item $fullPath).GetAccessControl('Access')

            Write-Host "Cert:\n" + $cert
            Write-Host "CertHash:\n" + $certHash
            Write-Host "CertSubject:\n" + $certSubject
            Write-Host "keyName:\n" + $keyName
            Write-Host "fullPath:\n" + $fullPath
            Write-Host "acl:\n" + $acl
 
            $hasPermissionsAlready = ($acl.Access | where {$_.IdentityReference.Value.Contains($userGroup.ToUpperInvariant()) -and $_.FileSystemRights -eq [System.Security.AccessControl.FileSystemRights]::FullControl}).Count -eq 1
         
            if ($hasPermissionsAlready){
                Write-Host "Certificate '$certSubject' already has the FullControl permissions to group $userGroup." -ForegroundColor Green
            } else {
                $acl.AddAccessRule($rule)
                Set-Acl -Path $fullPath -AclObject $acl
            }
        }
        Write-Host "Completed Setting Local Machine Private Key Permissions to FullControl for Everyone"

        ##############################################
        # Sets the IPAddress and gateway for the VMs #
        ##############################################

        Write-Host "Setting gateway for IPAddress"
        # This should be run last after a vagrant reload. vagrant reload wipes this setting for some reason
        netsh interface ipv4 set address name="$domainNet" static ([IPAddress]$IPAddress) 255.255.255.0 ([IPAddress]$GatewayIP.Trim())
        Write-Host "Completed setting gateway for IPAddress"
     }
} catch { 
    $_
    write-host "found error"
} 

Get-PSSession | Where-Object { $_.Name -ne 'WinPSCompatSession' -and $_.State -ne 'Disconnected'} | Remove-PSSession