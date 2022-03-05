#!/bin/bash
### 
# Filename:  otgnet.sh
# 
# This script takes care of adding the usb0 ethernet passthru DHCP range to /etc/dnsmasq.conf
# ... so that the main dnsmasq service will listen for DHCP requests for ap0 and usb0 on pikvm
#
# This is downloaded and run by the hotspot[.rpi] scripts
###
DHCPRANGE=$( systemctl status kvmd-otgnet | grep range | awk -F'range=' '{print $2}' | cut -d' ' -f1 | uniq )
if [[ $DHCPRANGE == "" ]]; then
        echo "No otgnet: overrides found.  Exiting."
        exit 1
fi

### Create entry for use with dnsmasq for the usb network passthru adapter ###
DHCPUSB0="dhcp-range=interface:usb0,$DHCPRANGE"

if [[ $( grep -c $DHCPUSB0 /etc/dnsmasq.conf ) -ne 1 ]]; then
    # disable kvmd-otgnet-dnsmasq before adding entry and restarting dnsmasq
    systemctl disable kvmd-otgnet-dnsmasq

    echo "-> Missing entry in /etc/dnsmasq.conf.  Adding and restarting dnsmasq ..."
    if [ $( grep -i ^name= /etc/os-release | cut -d'"' -f 2 | cut -d' ' -f 1 ) == "Arch" ]; then rw; fi
    echo "# Add DHCP entry for usb ethernet passthru adapter" >> /etc/dnsmasq.conf
    echo $DHCPUSB0 >> /etc/dnsmasq.conf
    if [ $( grep -i ^name= /etc/os-release | cut -d'"' -f 2 | cut -d' ' -f 1 ) == "Arch" ]; then ro; fi

    systemctl restart dnsmasq
else
    echo "Entry already in /etc/dnsmasq.conf"
fi
echo $DHCPUSB0

tail /var/lib/misc/dnsmasq.log
