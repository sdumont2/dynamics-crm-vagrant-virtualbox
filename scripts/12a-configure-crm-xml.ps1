Param(
    $dbServerHostname,
    $domainNet,
    $distinguishedOU,
    $plaintextPass
)

New-Item -ItemType File -Path "C:\crmsetup\crmconfig.xml" -Force

$crmConfigFile = "C:\crmsetup\crmconfig.xml"

Set-Content $crmConfigFile -Force -Value '<CRMSetup>'
Add-Content $crmConfigFile -Value '    <Server>'
Add-Content $crmConfigFile -Value '        <Patch update="false" />'
Add-Content $crmConfigFile -Value '        <LicenseKey>KKNV2-4YYK8-D8HWD-GDRMW-29YTW</LicenseKey>'
Add-Content $crmConfigFile -Value "        <SqlServer>$dbServerHostname</SqlServer>"
Add-Content $crmConfigFile -Value '        <Database create="true" />'
Add-Content $crmConfigFile -Value "        <Reporting URL=`"http://$dbServerHostname/ReportServer`" />"
Add-Content $crmConfigFile -Value '        <OrganizationCollation>Latin1_General_CI_AI</OrganizationCollation>'
Add-Content $crmConfigFile -Value '        <basecurrency isocurrencycode="USD" currencyname="US Dollar" currencysymbol="$" currencyprecision="2" />'
Add-Content $crmConfigFile -Value '        <Organization>ContosoCom</Organization>'
Add-Content $crmConfigFile -Value '        <OrganizationUniqueName>contosoCom</OrganizationUniqueName>'
Add-Content $crmConfigFile -Value '        <WebsiteUrl create="true" port="5555"> </WebsiteUrl>'
Add-Content $crmConfigFile -Value '        <InstallDir>c:\Program Files\Microsoft Dynamics CRM</InstallDir>'
Add-Content $crmConfigFile -Value '        <CrmServiceAccount type="DomainUser">'
Add-Content $crmConfigFile -Value "            <ServiceAccountLogin>$domainNet\CRMAppService</ServiceAccountLogin>"
Add-Content $crmConfigFile -Value "            <ServiceAccountPassword>$plaintextPass</ServiceAccountPassword>"
Add-Content $crmConfigFile -Value '        </CrmServiceAccount>'
Add-Content $crmConfigFile -Value '        <SandboxServiceAccount type="DomainUser">'
Add-Content $crmConfigFile -Value "            <ServiceAccountLogin>$domainNet\CRMSandboxService</ServiceAccountLogin>"
Add-Content $crmConfigFile -Value "            <ServiceAccountPassword>$plaintextPass</ServiceAccountPassword>"
Add-Content $crmConfigFile -Value '        </SandboxServiceAccount>'
Add-Content $crmConfigFile -Value '        <DeploymentServiceAccount type="DomainUser">'
Add-Content $crmConfigFile -Value "            <ServiceAccountLogin>$domainNet\CRMDeploymentService</ServiceAccountLogin>"
Add-Content $crmConfigFile -Value "            <ServiceAccountPassword>$plaintextPass</ServiceAccountPassword>"
Add-Content $crmConfigFile -Value '        </DeploymentServiceAccount>'
Add-Content $crmConfigFile -Value '        <AsyncServiceAccount type="DomainUser">'
Add-Content $crmConfigFile -Value "            <ServiceAccountLogin>$domainNet\CRMAsyncService</ServiceAccountLogin>"
Add-Content $crmConfigFile -Value "            <ServiceAccountPassword>$plaintextPass</ServiceAccountPassword>"
Add-Content $crmConfigFile -Value '        </AsyncServiceAccount>'
Add-Content $crmConfigFile -Value '        <VSSWriterServiceAccount type="DomainUser">'
Add-Content $crmConfigFile -Value "            <ServiceAccountLogin>$domainNet\CRMVSSWriterService</ServiceAccountLogin>"
Add-Content $crmConfigFile -Value "            <ServiceAccountPassword>$plaintextPass</ServiceAccountPassword>"
Add-Content $crmConfigFile -Value '        </VSSWriterServiceAccount>'
Add-Content $crmConfigFile -Value '        <MonitoringServiceAccount type="DomainUser">'
Add-Content $crmConfigFile -Value "            <ServiceAccountLogin>$domainNet\CRMMonitoringService</ServiceAccountLogin>"
Add-Content $crmConfigFile -Value "            <ServiceAccountPassword>$plaintextPass</ServiceAccountPassword>"
Add-Content $crmConfigFile -Value '        </MonitoringServiceAccount>'
Add-Content $crmConfigFile -Value '        <SQM optin="false" />'
Add-Content $crmConfigFile -Value '        <muoptin optin="false" />'
Add-Content $crmConfigFile -Value '        <Groups AutoGroupManagementOff="false">'
Add-Content $crmConfigFile -Value "            <PrivUserGroup>CN=PrivUserGroup,OU=CRM,$distinguishedOU</PrivUserGroup>"
Add-Content $crmConfigFile -Value "            <SQLAccessGroup>CN=SQLAccessGroup,OU=CRM,$distinguishedOU</SQLAccessGroup>"
Add-Content $crmConfigFile -Value "            <ReportingGroup>CN=ReportingGroup,OU=CRM,$distinguishedOU</ReportingGroup>"
Add-Content $crmConfigFile -Value "            <PrivReportingGroup>CN=PrivReportingGroup,OU=CRM,$distinguishedOU</PrivReportingGroup>"
Add-Content $crmConfigFile -Value '        </Groups>'
Add-Content $crmConfigFile -Value '    </Server>'
Add-Content $crmConfigFile -Value '</CRMSetup>'
