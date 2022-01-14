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

$mainScriptSession = New-PSSession -ComputerName $env:COMPUTERNAME -Credential $ADUserCredential -Authentication Credssp
try { 
    Invoke-Command -Session $mainScriptSession -ArgumentList $domainNet, $vagrantUsername -ScriptBlock {
        Param(
            $domainNet,
            $vagrantUsername
        )
        Set-ExecutionPolicy Bypass -Scope Process -Force

        New-Item -ItemType Directory -Path C:\office
        Copy-Item C:\vagrant\install\sql.iso C:\office\

        Write-Host "Creating SQL Config"
        & C:\vagrant\scripts\10aa-create-sql-install-config.ps1 $domainNet $vagrantUsername

        #Installs SQL Server locally with standard settings for Developers/Testers.
        # Install SQL from command line help - https://msdn.microsoft.com/en-us/library/ms144259.aspx
        $startTime = Get-Date
        Write-Host "Starting at: $startTime"
        # Without this then the install will run, but the script will execute/finish before the install is done
        Write-Host "Images mounted"
        & C:\vagrant\scripts\10ab-install-sql-internal.ps1 $domainNet

        Write-Host "SQL Installation Complete"
    }
} catch { 
    $_
    write-host "found error"
} 

Exit 0