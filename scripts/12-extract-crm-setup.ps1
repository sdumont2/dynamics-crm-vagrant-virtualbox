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

$adDomain = Get-ADDomain -Server $domain
$distinguishedOU = $adDomain.DistinguishedName

$pw = ConvertTo-SecureString "$plaintextPass" -AsPlainText -Force
$ADUserCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "$domainNet\$vagrantUsername",$pw 

$dbServerHostname = $env:COMPUTERNAME

$mainScriptSession = New-PSSession -ComputerName $dbServerHostname -Credential $ADUserCredential -Authentication Credssp
try { 
    Invoke-Command -Session $mainScriptSession -ArgumentList $dbServerHostname, $domainNet, $distinguishedOU, $plaintextPass -ScriptBlock {
        Param(
            $dbServerHostname,
            $domainNet,
            $distinguishedOU,
            $plaintextPass
        )

        Set-ExecutionPolicy Bypass -Scope Process -Force
        #extracting files from crm server exe
        $crmExists = test-path C:\vagrant\install\CRM9.0-Server-ENU-amd64.exe
        $output = "C:\vagrant\install\CRM9.0-Server-ENU-amd64.exe"
        $url = "https://download.microsoft.com/download/B/D/0/BD0FA814-9885-422A-BA0E-54CBB98C8A33/CRM9.0-Server-ENU-amd64.exe"

        $ldExists = test-path C:\extLog
        if ($ldExists -eq $false) {
            New-Item -Path C:\extLog -Type Directory -Force #Should exist already but just in case
        }

        ##
        Write-Host "Installing Prerequisites"
        New-Item C:\prereqs\ -ItemType Directory -Force
        Copy-Item C:\vagrant\install\vcredist_x64_2013.exe C:\prereqs\
        Copy-Item C:\vagrant\install\vcredist_x64_2010.exe C:\prereqs\
        Copy-Item C:\vagrant\install\odbc2013.msi C:\prereqs\
        Copy-Item C:\vagrant\install\sqlncli2012.msi C:\prereqs\
        C:\prereqs\vcredist_x64_2013.exe /Quiet /Install /Norestart
        C:\prereqs\vcredist_x64_2010.exe /s /Install /Norestart
        New-Item -ItemType File -Path C:\extLog\odbc.log -Force
        C:\prereqs\odbc2013.msi /QN ADDLOCAL=ALL IACCEPTMSODBCSQLLICENSETERMS=YES /L*v C:\extLog\odbc.log
        C:\prereqs\sqlncli2012.msi /QN IACCEPTSQLNCLILICENSETERMS=YES
        Write-Host "Completed Installing Prerequisites"
        ##

        if($crmExists -eq $false){
            Import-Module BitsTransfer
            Start-BitsTransfer -Source $url -Destination $output
        }

        $logExists = test-path C:\extLog\log1.txt
        if($logExists -eq $false){
            New-Item -ItemType File -Path C:\extLog\log1.txt -Force
        }

        New-Item -ItemType directory -Path C:\crmsetup -Force
        & C:\vagrant\install\CRM9.0-Server-ENU-amd64.exe /quiet /extract:C:\crmsetup\ /log:C:\extLog\log1.txt

        C:\vagrant\scripts\12a-configure-crm-xml.ps1 $dbServerHostname $domainNet $distinguishedOU 'zaq1@WSX'

        $contentReady = $false
        while ($contentReady -eq $false){

            $itemsCount = ( Get-ChildItem C:\crmsetup  ).Count;

            if ($itemsCount -gt 0){
                $contentReady = $true
            }
        }

        $contentReady = $false
        while($contentReady -eq $false){
            $matches = Select-String -Path C:\extLog\log1.txt -Pattern "Done extracting the files"
            
            if ( $matches.Length -gt 0 ){
                $contentReady = $true
            }else{
                Write-Host "Waiting for files extraction completion"
            }
            Write-Host $matches
            Start-Sleep -Seconds 30
        }
        Write-Host "All files extracted - ready for crm installation"

    }
} catch { 
    $_
    write-host "found error"
} 
Start-Sleep -Seconds 30

Exit 0