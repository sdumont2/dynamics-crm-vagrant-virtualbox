#####################################
# Adding DNS Entries for the server #
#####################################
Param (
    $zoneName,
    [String]$zonesToAddJson
)

#Waiting For Domain services to be up
Start-Sleep -Seconds 20
while ($true) {
    if ((Get-Service -Name ADWS -ErrorAction SilentlyContinue).Status -eq 'Running') {
        try {
            $env:ADPS_LoadDefaultDrive = 0
            $WarningPreference = 'SilentlyContinue'
            Import-Module -Name ActiveDirectory -ErrorAction Stop
            Get-ADDomain | Out-Null
            break
        } catch {
            Start-Sleep -Seconds 20
        }
    } else {
        Start-Sleep -Seconds 20
    }
}

Set-ExecutionPolicy Bypass -Scope Process

Get-DnsServerDiagnostics

$zonesToAdd = $zonesToAddJson | ConvertFrom-Json -Verbose
$aZones = $($zonesToAdd.aZones)
$cNameZones = $($zonesToAdd.cNameZones)
# A zones first, so the CNames can bind to any azones that are created
foreach ($zone in $aZones) {
    Add-DnsServerResourceRecord -ZoneName $zoneName -A -Name $($zone.name) -IPv4Address $($zone.target)
}
foreach ($zone in $cNameZones) {
    Add-DnsServerResourceRecord -ZoneName $zoneName -CName -Name $($zone.name) -HostNameAlias $($zone.target)
}

Exit 0