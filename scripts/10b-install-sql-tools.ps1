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
    Invoke-Command -Session $mainScriptSession -ScriptBlock {
        Set-ExecutionPolicy Bypass -Scope Process -Force

        Write-Host "Installing SQL Report Server..."
        New-Item -ItemType File -Path C:\DeployDebug\sqlreportbuilderinstalllog.txt -Force
        Copy-Item C:\vagrant\install\ReportBuilder.msi C:\office\
        C:\office\ReportBuilder.msi /quiet /norestart /L*v C:\DeployDebug\sqlreportbuilderinstalllog.txt

        Write-Host "Installing SQL Server Reporting Services..."
        Copy-Item C:\vagrant\install\SQLServerReportingServices.exe C:\office\ 
        C:\office\SQLServerReportingServices.exe /Install /Quiet /Norestart /IAcceptLicenseTerms

        Write-Host "Installing SQL Server Management Studio..."
        Copy-Item C:\vagrant\install\SSMS-Setup-ENU.exe C:\office\ 
        C:\office\SSMS-Setup-ENU.exe /Install /Quiet /Norestart

        Write-Host "Installing SQL Clr Types..."
        New-Item -ItemType File -Path C:\DeployDebug\sqlclrinstalllog.txt -Force
        Copy-Item C:\vagrant\install\SQLSysClrTypes.msi C:\office\
        C:\office\SQLSysClrTypes.msi /quiet /norestart /L*v C:\DeployDebug\sqlclrinstalllog.txt

        Write-Host "Now installing SMO..."
        New-Item -ItemType File -Path C:\DeployDebug\smoinstalllog.txt -Force
        Copy-Item C:\vagrant\install\SharedManagementObjects.msi C:\office\
        C:\office\SharedManagementObjects.msi /quiet /norestart /L*v C:\DeployDebug\smoinstalllog.txt

        Write-Host "Done installing SMO"

        ##
        Write-Host "Installing sql post-requisites"
        New-Item C:\prereqs\ -ItemType Directory -Force
        #dotnet 4.8 
        Copy-Item C:\vagrant\install\ndp48-x86-x64-allos-enu.exe C:\prereqs\
        #cpp 2017 64/32
        Copy-Item C:\vagrant\install\vcredist_x64_2017.exe C:\prereqs\
        Copy-Item C:\vagrant\install\vcredist_x86_2017.exe C:\prereqs\
        #cpp 2015 64/32
        Copy-Item C:\vagrant\install\vcredist_x64_2015.exe C:\prereqs\
        Copy-Item C:\vagrant\install\vcredist_x86_2015.exe C:\prereqs\
        Copy-Item C:\vagrant\install\odbc2013.msi C:\prereqs\
        Copy-Item C:\vagrant\install\sqlncli2012.msi C:\prereqs\
        C:\prereqs\ndp48-x86-x64-allos-enu.exe /q /norestart /log C:\DeployDebug\dotnet48.txt
        C:\prereqs\vcredist_x86_2015.exe /quiet /norestart /log C:\DeployDebug\cpp32_2015.log
        C:\prereqs\vcredist_x64_2015.exe /quiet /norestart /log C:\DeployDebug\cpp64_2015.log
        C:\prereqs\vcredist_x86_2017.exe /quiet /norestart /log C:\DeployDebug\cpp32_2017.log
        C:\prereqs\vcredist_x64_2017.exe /quiet /norestart /log C:\DeployDebug\cpp64_2017.log
        Write-Host "Completed Installing sql post-requisites"
        ##
    }
} catch { 
    $_
    write-host "found error"
} 

Exit 0