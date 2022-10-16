{
    #-------------------------------------------------------------------------------
    #
    # The purpose of this script is to create a vlan based
    # configuration for ROS which can be built on by this script.
    #
    #-------------------------------------------------------------------------------
    # Set the name of the router
    :local systemName "ispbills"

    # Secure your RouterOS! Set the password you would like to use when logging on as 'admin'.
    :local adminPassword "Admin121"

    # Time Servers (NTP)
    :local ntpA "173.230.149.23"
    :local ntpB "198.110.48.12"

    # Name Servers (DNS) - set to OpenDNS. This should be set to a set of servers that are local and FAST 
    :local nsA "8.8.8.8"
    :local nsB "8.8.4.4"
    :local nsC "1.1.1.1"

    # DHCP - Automatically set if package is installed
    #:local dhcpServer ""
    #:local lanPoolName ""
    #:local poolStart "192.168.10.100"
    #:local poolEnd "192.168.10.150"

    #:local lanAddress "192.168.10.1"
    #:local lanNetworkAddress "192.168.10.0"
    #:local lanNetworkBits "24"

    # Interfaces
    :local sfp1 "sfp1"
    :local ether2 "ether2-master-local"
    :local ether3 "ether3-slave-local"
    :local ether4 "ether4-slave-local"
    :local ether5 "ether5-slave-local"

    # SSH
    :local sshPort 22

    #-------------------------------------------------------------------------------
    #
    # Configuration
    #
    #-------------------------------------------------------------------------------
    :log info "--- ISPbills automation started ---";
    :log info "--- DO NOT Power off or Cancell ---";
    :log info "--- Setting timezone ---";
    /system clock set time-zone-autodetect=yes

    :log info "--- Setting up the time server client ---";
    /system ntp client set enabled=yes primary-ntp=$ntpA secondary-ntp=$ntpB

    :log info "--- Setting the system name ---";
    /system identity set name=$systemName;

    :log info "--- Setting the admin password ---";
    /user set admin password=$adminPassword;

    :log info "--- Clearing all pre-existing settings ---";
    /ip firewall {
      :log info "--- Clearing any existing NATs ---";
      :local o [nat find]
      :if ([:len $o] != 0) do={ nat remove numbers=$o }

      :log info "--- Clearing old filters ---";
      :local o [filter find where dynamic=no]
      :if ([:len $o] != 0) do={ filter remove $o }

      :log info "--- Clearing old address lists ---";
      :local o [address-list find]
      :if ([:len $o] != 0) do={ address-list remove numbers=$o }

      :log info "--- Clearing previous mangles ---";
      :local o [mangle find where dynamic=no]
      :if ([:len $o] != 0) do={ mangle remove numbers=$o }

      :log info "--- Clearing previous layer-7 ---";
      :local o [layer7-protocol find]
      :if ([:len $o] != 0) do={ layer7-protocol remove numbers=$o }
    }

    :log info "--- Resetting Mac Server ---";
    /tool mac-server set allowed-interface-list=all
    /tool mac-server mac-winbox set allowed-interface-list=all

    :log info "--- Resetting neighbor discovery ---";
    /ip neighbor discovery-settings set discover-interface-list=all

    #-------------------------------------------------------------------------------
    #
    # Setting the ethernet interfaces
    # Ethernet Port 1 is used as the WAN port and is designated the gateway to DSL/Cable Modem
    # DHCP client and masquerde is enabled on ether1
    # Ethernet port 2 is used as the switch master for the remain three ports
    #
    #-------------------------------------------------------------------------------

    :log info "--- Reset interfaces to default ---";
    :foreach iface in=[/interface ethernet find] do={
      /interface ethernet set $iface name=[get $iface default-name]
    }

    :log info "--- Remove old DHCP client ---";
    :local o [/ip dhcp-client find]
    :if ([:len $o] != 0) do={ /ip dhcp-client remove $o }

    :log info "--- Setup the wired interface(s) ---";
    /interface set sfp1 name="$sfp1";

    :log info "--- Setting up vlans on the gateway interface ---";
    /interface vlan add interface=sfp1 name=bdix vlan-id=604
    /interface vlan add interface=sfp1 name=fna vlan-id=603
    /interface vlan add interface=sfp1 name=ggc vlan-id=602
    /interface vlan add interface=sfp1 name=iig vlan-id=601

    #-------------------------------------------------------------------------------
    #
    # DHCP Server
    # configure the server on the lan interface for handing out ip to both
    # lan and wlan. Address pool is defined above with $poolStart and $poolEnd.
    #
    #-------------------------------------------------------------------------------
    :local o [/ip dhcp-server network find]
    :if ([:len $o] != 0) do={ /ip dhcp-server network remove $o }

    :local o [/ip dhcp-server find]
    :if ([:len $o] != 0) do={ /ip dhcp-server remove $o }

    :local o [/ip pool find]
    :if ([:len $o] != 0) do={ /ip pool remove $o }

    /ip dns {
      set allow-remote-requests=no
      :local o [static find]
      :if ([:len $o] != 0) do={ static remove $o }
    }

    /ip address {
      :local o [find]
      :if ([:len $o] != 0) do={ remove $o }
    }

    :log info "--- Setting the routers IP address to vlans ---";
    /ip address add address=172.18.203.14/30 interface=ggc network=172.18.203.12
    /ip address add address=172.18.203.18/30 interface=fna network=172.18.203.16
    /ip address add address=172.18.203.22/30 interface=bdix network=172.18.203.20
    /ip address add address=103.134.31.50/30 interface=iig network=103.134.31.48

    :log info "--- Setting DNS servers to $nsA and $nsB ---";
    /ip dns {
      set allow-remote-requests=yes servers="$nsA,$nsB,$nsC";
      #static add name=$systemName address=$lanAddress;
    }


    #-------------------------------------------------------------------------------
    #
    # Firewall
    #
    #-------------------------------------------------------------------------------

    :log info "--- Setting up NAT on WAN interface ---";
    /ip firewall nat {
    add action=masquerade chain=srcnat out-interface=bdix
    add action=masquerade chain=srcnat out-interface=ggc
    add action=masquerade chain=srcnat out-interface=fna
    add action=masquerade chain=srcnat out-interface=iig to-addresses=103.134.31.50 }

    :log info "--- Setting up simple firewall rules ---";
    /ip firewall {
      filter add chain=input action=accept connection-state=established,related comment="Allow established connections"
      filter add chain=input action=drop in-interface=$ether1
      filter add chain=forward action=fasttrack-connection connection-state=established,related
      filter add chain=forward action=accept connection-state=established,related
      filter add chain=forward action=drop connection-state=invalid
      filter add chain=forward action=drop connection-state=new connection-nat-state=!dstnat in-interface=$ether1
    }
    #-------------------------------------------------------------------------------
    #
    # Harden Router
    #
    #-------------------------------------------------------------------------------
    :log info "--- Enable neighbor discovery ---";
    /ip neighbor discovery-settings set discover-interface-list=all

    :log info "--- Disabling bandwidth test server ---";
    /tool bandwidth-server set enabled=no;

    :log info "--- Disabling firewall service ports ---";
    /ip firewall service-port {
      :foreach o in=[find where !disabled and name!=sip and name!=pptp] do={
        set $o disabled=yes;
      }
    }

    :log info "--- Disable mac server tools ---";
    :log info "Auto configuration ended.";
    :put "";
    :put "Auto configuration ended. Please check the system log.";
    /file remove [/file find name=(core_setup.rsc)]
    /system reboot;
}