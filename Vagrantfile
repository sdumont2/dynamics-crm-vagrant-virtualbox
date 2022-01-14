################################
# Dynamics Vagrant with Claims #
################################

# Variables That shouldn't change
$BASE_BOX           = "gusztavvargadr/windows-server-2016-standard-desktop"
$BASE_BOX_VERSION   = "1607.0.2110"
$BASE_BOX_LOCAL     = "base-windows-server-box"

# Variables that CAN change, but likely won't
$VAGRANT_IP_PATTERN = "10.0.*"
$DOMAIN_NAME        = "contoso.com"
$NETBIOS_NAME       = "contoso"

# Variables That will change depending on the environment

# Your local internet adapter, to bridge with the VMs
$BRIDGE_IF          = [ "en5: Thunderbolt Ethernet Slot 1", "en0: Wi-Fi" ]

# IP Address space (use the one attached to the adapter you're using)
$NET_PREFIX         = "10.1.10"
$GATEWAY_IP         = "10.1.10.1"

# Choose IP Addresses you're not using
$DC1_IP             = "#{$NET_PREFIX}.122"
$NODE_IP            = "#{$NET_PREFIX}.123"
$NET_PATTERN        = "#{$NET_PREFIX}.*"
$NET_ADDRESS_SPACE  = "#{$NET_PREFIX}.0"

# JSON Object Representing the DNS records to create
# Likely won't change
$DNS_RECORDS_JSON = "{
    'aZones': [
        {
            'name': 'adfs',
            'target': '#{$DC1_IP}'
        }
    ],
    'cNameZones': [
        {
            'name': 'enterpriseregistration',
            'target': 'adfs.#{$DOMAIN_NAME}'
        }
    ]
}"

# Admin user and pasword
$USERNAME = "vagrant"
$PASSWORD = "vagrant"

Vagrant.configure("2") do |config|
    # winrm config
    config.winrm.retry_limit = 50
    config.winrm.retry_delay = 20
    config.winrm.timeout = 36000
    config.winrm.transport = :plaintext
    config.winrm.basic_auth_only = true
    config.winrm.username = $USERNAME
    config.winrm.password = $PASSWORD

    config.vm.boot_timeout = 120000

    config.vm.define "dc1" do |dc1|
        dc1.vm.box = $BASE_BOX_LOCAL
        dc1.vm.hostname = "dc1"
        dc1.vm.provider "virtualbox" do |vb|
            vb.name = "dc1"
            vb.memory = "2048"
            vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
            vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
            vb.customize ["modifyvm", :id, "--memory", 2048]
        end

        dc1.vm.network :public_network, ip: $DC1_IP, bridge: $BRIDGE_IF, gateway: $GATEWAY_IP, dns: $DC1_IP 

        dc1.vm.provision "shell", path: "scripts/01-common-script.ps1", args: [$DC1_IP, $GATEWAY_IP, $NET_PATTERN, $NETBIOS_NAME]    
        dc1.vm.provision :reload
        dc1.vm.provision "shell", path: "scripts/02-install-ad-ds.ps1", args: [$DOMAIN_NAME, $NETBIOS_NAME, $PASSWORD]     
        dc1.vm.provision :reload
        dc1.vm.provision "shell", path: "scripts/03-populate-dns.ps1", args: [$DOMAIN_NAME, $DNS_RECORDS_JSON]
        dc1.vm.provision "shell", path: "scripts/04-populate-ad.ps1", args: ["node", $NET_ADDRESS_SPACE, $USERNAME, $PASSWORD]
        dc1.vm.provision "shell", path: "scripts/02a-install-ad-ds-cleanup.ps1", args: [$DC1_IP, $GATEWAY_IP, $NET_PATTERN, $NETBIOS_NAME, $USERNAME, $PASSWORD] 
        dc1.vm.provision :reload
        dc1.vm.provision "shell", path: "scripts/06-install-ad-cs.ps1", args: [$DOMAIN_NAME, $NETBIOS_NAME, $USERNAME, $PASSWORD]   
        dc1.vm.provision :reload
        dc1.vm.provision "shell", path: "scripts/08-install-adfs.ps1", args: [$DOMAIN_NAME, $NETBIOS_NAME, $USERNAME, $PASSWORD]
        dc1.vm.provision :reload
        dc1.vm.provision "shell", path: "scripts/08a-populate-adfs.ps1", args: [$DOMAIN_NAME, $NETBIOS_NAME, $USERNAME, $PASSWORD]
        dc1.vm.provision :reload
        dc1.vm.provision "shell", path: "scripts/01a-common-script-ending.ps1", args: [$DOMAIN_NAME, $NETBIOS_NAME, $DC1_IP, $GATEWAY_IP, $USERNAME, $PASSWORD]   
    end

    config.vm.define "node" do |node|
        node.vm.box = $BASE_BOX_LOCAL
        node.vm.hostname = "node"
        node.vm.provider "virtualbox" do |vb|
            vb.name = "node"
            vb.memory = "8192"
            vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
            vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
            vb.customize ["modifyvm", :id, "--memory", 8192]
        end
        
        node.vm.network :public_network, ip: $NODE_IP, bridge: $BRIDGE_IF, gateway: $GATEWAY_IP, dns: $DC1_IP  

        node.vm.provision "shell", path: "scripts/01-common-script.ps1", args: [$NODE_IP, $GATEWAY_IP, $NET_PATTERN, $NETBIOS_NAME]
        node.vm.provision :reload    
        node.vm.provision "shell", path: "scripts/07-join-to-domain.ps1", args: [$NETBIOS_NAME, $DC1_IP, $DOMAIN_NAME, "dc1", $USERNAME, $PASSWORD]  
        node.vm.provision :reload
        node.vm.provision "shell", path: "scripts/07a-post-domain-join.ps1", args: [$DOMAIN_NAME, $NETBIOS_NAME, "dc1", $DC1_IP, $USERNAME, $PASSWORD] 
        node.vm.provision :reload
        node.vm.provision "shell", path: "scripts/10-install-sql-pre-reqs.ps1", args: [$DOMAIN_NAME, $NETBIOS_NAME, $USERNAME, $PASSWORD]
        node.vm.provision :reload
        node.vm.provision "shell", path: "scripts/10a-install-sql.ps1", args: [$DOMAIN_NAME, $NETBIOS_NAME, $USERNAME, $PASSWORD]
        node.vm.provision :reload
        node.vm.provision "shell", path: "scripts/10b-install-sql-tools.ps1", args: [$DOMAIN_NAME, $NETBIOS_NAME, $USERNAME, $PASSWORD]
        node.vm.provision "shell", path: "scripts/11-ssrs-auto-configuration.ps1"
        node.vm.provision "shell", path: "scripts/12-extract-crm-setup.ps1", args: [$DOMAIN_NAME, $NETBIOS_NAME, $USERNAME, $PASSWORD]
        node.vm.provision :reload      
        node.vm.provision "shell", path: "scripts/13-install-crm.ps1", args: [$DOMAIN_NAME, $NETBIOS_NAME, $USERNAME, $PASSWORD]
        node.vm.provision :reload
        node.vm.provision "shell", path: "scripts/14-configure-crm.ps1", args: [$DOMAIN_NAME, $NETBIOS_NAME, "dc1", $USERNAME, $PASSWORD]
        node.vm.provision :reload
        node.vm.provision "shell", path: "scripts/01a-common-script-ending.ps1", args: [$DOMAIN_NAME, $NETBIOS_NAME, $NODE_IP, $GATEWAY_IP, $USERNAME, $PASSWORD] 
   end
  end