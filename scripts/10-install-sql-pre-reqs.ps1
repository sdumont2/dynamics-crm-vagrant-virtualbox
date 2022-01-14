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

        ###############################
        # Installs .NET 3.5 Framework #
        ###############################

        Write-Host "Installing .NET 3.5 Framework"
        Install-WindowsFeature -Name Net-Framework-Core -IncludeManagementTools
        Write-Host "Completed Installing .NET 3.5 Framework"
        
    }
} catch { 
    $_
    write-host "found error"
} 

Exit 0