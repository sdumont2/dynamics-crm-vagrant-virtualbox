# Microsoft Dynamics 365 Trial Environment Vagrant/Virtualbox

##Overview
The purpose of this project is to get a test/dev/trial environment set up in Virtualbox with a Windows Server Domain, and ADFS with Claims Based Auth set up for a Microsoft Dynamics CRM on premise environment.

If you already have all/most of the files. Shorter instructions are here:
```
brew install --cask virtualbox
brew install --cask vagrant
download the virtualbox image here: https://app.vagrantup.com/gusztavvargadr/boxes/windows-server-standard/versions/1607.0.2108/
put the virtualbox image in the same level as the Vagrantfile
vagrant plugin install vagrant-reload
vagrant box add base-windows-server-box file://(pwd)/base-windows-server-box.box
Follow the directions in the Network Settings part of the README
vagrant up dc1
vagrant up node
Follow post build instructions
```

Some files are not provided, but can be downloaded from Microsoft at the below links:

####Install Scripts Requirements
[SysInternalsSuite (leave as a zip)](https://download.sysinternals.com/files/SysinternalsSuite.zip)

####SQL Resources
- [SQL Server 2016 Developer Edition with Service Pack 2 ISO File (Requires an account (It's completely free)). Make sure the file is renamed to `sql.iso`](https://my.visualstudio.com/Downloads?q=SQL%20Server%202016%20Developer)
- [.NET 4.8 Download](https://download.visualstudio.microsoft.com/download/pr/7afca223-55d2-470a-8edc-6a1739ae3252/abd170b4b0ec15ad0222a809b761a036/ndp48-x86-x64-allos-enu.exe)
- [C++ VC Redist 64 2017 (rename file to `vcredist_x64_2017.exe`)](https://aka.ms/vs/15/release/vc_redist.x64.exe)
- [C++ VC Redist 32 2017 (rename file to `vcredist_x86_2017.exe`)](https://aka.ms/vs/15/release/vc_redist.x86.exe)
- [C++ VC Redist 64 2015 (rename file to `vcredist_x64_2015.exe`)](https://download.microsoft.com/download/6/A/A/6AA4EDFF-645B-48C5-81CC-ED5963AEAD48/vc_redist.x64.exe)
- [C++ VC Redist 32 2015 (rename file to `vcredist_x86_2015.exe`)](https://download.microsoft.com/download/6/A/A/6AA4EDFF-645B-48C5-81CC-ED5963AEAD48/vc_redist.x86.exe)
- [SQL Server 2016 Management Studio (ensure file is named `SSMS-Setup-ENU.exe`)](https://go.microsoft.com/fwlink/?LinkID=840946)
- [SQL Server Report Builder](https://download.microsoft.com/download/5/E/B/5EB40744-DC0A-47C0-8B0A-1830E74D3C23/ReportBuilder.msi)
- [SQL Server Reporting Services](https://download.microsoft.com/download/E/6/4/E6477A2A-9B58-40F7-8AD6-62BB8491EA78/SQLServerReportingServices.exe)

####Microsoft Dynamics Pre-reqs
- [C++ VC Redist 64 2013 (rename file to `vcredist_x64_2013.exe`)](https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe)
- [C++ VC Redist 64 2010 (rename file to `vcredist_x64_2010.exe`)](http://go.microsoft.com/fwlink/?LinkId=404264&clcid=0x409)
- [SQL Server Native Client 2012 (rename file to `sqlncli2012.msi`)](https://download.microsoft.com/download/B/E/D/BED73AAC-3C8A-43F5-AF4F-EB4FEA6C8F3A/ENU/x64/sqlncli.msi)
- [SQL CLR Types 2016](https://download.microsoft.com/download/6/4/5/645B2661-ABE3-41A4-BC2D-34D9A10DD303/ENU/x64/SQLSysClrTypes.msi)
- [SQL Shared Management Objects 2016](https://download.microsoft.com/download/6/4/5/645B2661-ABE3-41A4-BC2D-34D9A10DD303/ENU/x64/SharedManagementObjects.msi)
- [ODBC 2013 (rename file to `odbc2013.msi`)](https://download.microsoft.com/download/D/5/E/D5EEF288-A277-45C8-855B-8E2CB7E25B96/x64/msodbcsql.msi)
- [Microsoft Dynamics 365 CRM exe (optional. will get downloaded if not present)](https://download.microsoft.com/download/B/D/0/BD0FA814-9885-422A-BA0E-54CBB98C8A33/CRM9.0-Server-ENU-amd64.exe)

##Prerequisites

- Virtualbox [can be downloaded here](https://virtualbox.org) or gotten via brew with the command `brew install --cask virtualbox`
- Vagrant `brew install --cask vagrant`
- Vagrant Reload Plugin `vagrant plugin install vagrant-reload`
- A basic/working knowledge of Windows/Powershell/Virtualbox/Vagrant/etc.

##Building

###Pre Build Instructions

####Getting Vagrant Ready
In the `Vagrantfile` is the box name and version I personally used. It's recommended that you [download the box file](https://app.vagrantup.com/gusztavvargadr/boxes/windows-server-standard/versions/1607.0.2108/) and have vagrant add it locally, so in the case of having to restart, you don't have to redownload the box file more than once.

The command to add a downloaded box locally (assuming the name of the box file is `base-windows-server-box.box`) is:
```
vagrant box add base-windows-server-box file://(pwd)/base-windows-server-box.box
```

####Network Settings
Edit the `BRIDGE_IF` to fit your needs (opening up virtualbox and looking at the "Bridge" network options to choose what you will use, in correspondence to your actual network interface that you're using).

With that you'll also need to change the `NET_PREFIX`, `GATEWAY_IP`, `DC1_IP`, and `NODE_IP` to match your network's internal IP settings

Additionally, You'll want to edit your hosts file in order to resolve the box hostnames locally (example below):
```
10.1.10.122 dc1.contoso.com
10.1.10.122 adfs.contoso.com
10.1.10.123 node.contoso.com
```
###Build/Run

`vagrant up dc1`

then

`vagrant up node`

if an error happens in the scripts can you need to start over. clear out the `certs` and `tmp` directories and then run

`vagrant destroy`

if an error happens, and you want to continue where you left off:
- comment out the scripts that hadn't run 
- then run  
  - `vagrant provision dc1`  
  or  
  - `vagrant provision node`  
   
  depending on where it errored out.

###Post Build Instructions

####Configuring Claims Based Authentication

- Some instructions available in the `14-configure-crm` script  
- https://docs.microsoft.com/en-us/dynamics365/customerengagement/on-premises/deploy/post-installation-configuration-guidelines-dynamics-365?view=op-9-1#register-the-client-apps
- https://idynamicsblog.com/2015/11/21/step-2-configuring-crm-to-use-claims-based-authentication/

####Java Keytool Cert Importing for Code usage
If interacting with Java code you'll either want to configure the Java SSL to accept Self Signed Certificate, or import the certificates into your java keystore.  

To import the certificates into the Java keystore you'll grab the adfs signing cert, and root ca crt from the certs/tmp directories, and also grab the cert issued to the CRM server in the final script (doing a certificate export and then enabling the virtualbox bidirectional drag/drop makes this extremely easy).  

Then you'll run this command for each file, changing the java path to match your desired java path, and then setting the alias and filename for each cert (just a note, the storepass for java is `changeit` by default, so unless you've changed it, it's probably still `changeit`):
```
keytool -import -trustcacerts -keystore /path/to/java/lib/security/cacerts -storepass changeit -noprompt -alias yourAliasName -file path\to\certificate.cer
```

##Acknowledgements

This setup and some of the scripts are inspired by [AutomatedLab](https://github.com/AutomatedLab/AutomatedLab)

##TODO

A lot


