#!/dev/null
########################################################################################################################
########################################################################################################################
##
##      Copyright (C) 2020 Peter Walsh, Milford, NH 03055
##      All Rights Reserved under the MIT license as outlined below.
##
##  FILE
##
##      Site::NetInfo.pm
##
##  DESCRIPTION
##
##      Return various network info structs
##
##  DATA
##
##      None.
##
##  FUNCTIONS
##
##      GetNetDevs()->[]    Return an array of network device names in the system (ie: [0]->"wlan0" )
##
##      GetWPAInfo()        Return array of WPA info
##          ->{Valid}           TRUE if WPA info file found
##          ->{SSID}            SSID of WiFi to connect
##          ->{KeyMgmt}         Key mgmt type         (ie: "WPA-PSK")
##          ->{Password}        Password to use with connection
##          ->{ Country}        Country code for Wifi (ie: "us")
##
##      SetWPAInfo($Info)   Write new WPA info with new values
##
##      GetDHCPInfo()       Return array of interface specifics from DHCPCD.conf
##          ->{Valid}           TRUE if DHCP info file found
##          ->{$IF}             Name of interface
##              ->{IPAddr}      Static IP address of interface
##              ->{Router}      Static router     of interface
##              ->{DNS1}        Static 1st DNS to use
##              ->{DNS2}        Static 2nd DNS to use
##    
##      SetDHCPInfo($Info)  Write new DHCP info with new values
##
##      GetNetEnable()->[]  Return array if enable/disable specifics from the netenable file
##          ->{Valid}           TRUE if netenable info file found
##          ->{$IF}             Points to interfaces entry for interface
##              ->"enable"      Value is "enable" or "disable"
##
##      SetNetEnable($Info) Write new netenable info with new values
##
########################################################################################################################
########################################################################################################################
##
##  MIT LICENSE
##
##  Permission is hereby granted, free of charge, to any person obtaining a copy of
##    this software and associated documentation files (the "Software"), to deal in
##    the Software without restriction, including without limitation the rights to
##    use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
##    of the Software, and to permit persons to whom the Software is furnished to do
##    so, subject to the following conditions:
##
##  The above copyright notice and this permission notice shall be included in
##    all copies or substantial portions of the Software.
##
##  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
##    INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
##    PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
##    HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
##    OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
##    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
##
########################################################################################################################
########################################################################################################################

package Site::NetInfo;
    use base "Exporter";

use strict;
use warnings;
use Carp;

use File::Slurp qw(read_file write_file);

use Site::ParseData;

our @EXPORT  = qw(&GetNetDevs
                  &GetWPAInfo
                  &SetWPAInfo
                  &GetDHCPInfo
                  &SetDHCPInfo
                  &GetNetEnable
                  &SetNetEnable
                  );          # Export by default

########################################################################################################################
########################################################################################################################
##
## Data declarations
##
########################################################################################################################
########################################################################################################################

our $DHCPConfigFile = "/etc/dhcpcd.conf";
our  $WPAConfigFile = "/etc/wpa_supplicant/wpa_supplicant.conf";
our   $NEConfigFile = "../etc/netenable";

#
# 1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
#     link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
# 2: eth0: <BROADCAST,MULTICAST> mtu 1500 qdisc mq state DOWN mode DEFAULT group default qlen 1000
#     link/ether dc:a6:32:33:cd:91 brd ff:ff:ff:ff:ff:ff
# 3: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP mode DORMANT group default qlen 1000
#     link/ether dc:a6:32:33:cd:92 brd ff:ff:ff:ff:ff:ff
#
our $DevMatches = [
    { RegEx => qr/^\d+:\s*(.+):\s*</, Action => Site::ParseData::AddVar },
    ];

#
# ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
# update_config=1
# country=US
#
# network={
# 	ssid="netname"
# 	psk="netpw"
# 	key_mgmt=WPA-PSK
#   }
#
our $WPAMatches = [
    {                     RegEx => qr/^\s*#/                  , Action => Site::ParseData::SkipLine }, # Skip comments
    { Name =>     "SSID", RegEx => qr/^\s*ssid\s*=\s*\"(.+)\"/, Action => Site::ParseData::AddVar   },
    { Name => "Password", RegEx => qr/^\s*psk\s*=\s*\"(.+)\"/ , Action => Site::ParseData::AddVar   },
    { Name =>  "KeyMGMT", RegEx => qr/^\s*key_mgmt\s*=\s*(.+)/, Action => Site::ParseData::AddVar   },
    { Name =>  "Country", RegEx => qr/^\s*country\s*=\s*(.+)/ , Action => Site::ParseData::AddVar   },
    ];

#
# interface wlan0
#     static ip_address=192.168.1.31/24
#     static routers=192.168.1.1
#     static domain_name_servers=1.1.1.1 1.0.0.1
#
our $DHCPMatches = [
    {                     RegEx  => qr/^\s*#/               , Action => Site::ParseData::SkipLine     }, # Skip Comments
    {                     RegEx  => qr/^\s*interface\s*(.+)/, Action => Site::ParseData::StartSection },
    { Name   => "IPAddr", RegEx  => qr/^\s*static\s*ip_address=(\d*\.\d*\.\d*\.\d*\/\d*)/,
                          Action => Site::ParseData::AddVar},
    { Name   => "Router", RegEx  => qr/^\s*static\s*routers=(\d*\.\d*\.\d*\.\d*)/        , 
                          Action => Site::ParseData::AddVar},
    { Name =>     "DNS1", RegEx  => qr/^\s*static\s*domain_name_servers\s*=\s*(\d*\.\d*\.\d*\.\d*)\s*\d*\.\d*\.\d*\.\d*/,
                          Action => Site::ParseData::AddVar},
    { Name =>     "DNS2", RegEx  => qr/^\s*static\s*domain_name_servers\s*=\s*\d*\.\d*\.\d*\.\d*\s*(\d*\.\d*\.\d*\.\d*)/,
                          Action => Site::ParseData::AddVar },
    ];

#
# wlan0:  disable
# wlan1:  enable
# eth0:   enable
#
our $NEMatches = [
    { RegEx => qr/^\s*#/                    , Action => Site::ParseData::SkipLine },   # Skip Comments
    { RegEx => qr/^(.*):\s*(enable|disable)/, Action => Site::ParseData::AddVar },
    ];

########################################################################################################################
########################################################################################################################
#
# GetNetDevs - Return list of network devices
#
# Inputs:   None.
#
# Outputs:  [Ref to] Array of network devices, by name
#
sub GetNetDevs {

    my $DevParse = Site::ParseData->new(Matches => $DevMatches);

    #
    # I don't *think* there's a way that this can be invalid, so didn't bother checking results.
    #
    $DevParse->ParseCommand("ip link show");

    my $NetDevs = [ keys %{$DevParse->AsHash()} ];

# use Data::Dumper;
# print Data::Dumper->Dump([$NetDevs],[qw(NetDevs)]);

    return $NetDevs;
    }


########################################################################################################################
########################################################################################################################
#
# GetWPAInfo - Return wpa_supplicant info
#
# Inputs:   None.
#
# Outputs:  [Ref to] struct of WPA supplicant info
#
# NOTE: This function can recognize a SINGLE set of credentials on a system. This is
#         consistent with Raspbian initial config using raspi-config. If your application
#         uses multiple sets of Wifi credentials, use a different function.
#
sub GetWPAInfo {

    return { Valid => 0 }
        unless -r $WPAConfigFile;

    my $ConfigFile = Site::ParseData->new(Filename => $WPAConfigFile, Matches  => $WPAMatches);
    my $WPAInfo    = $ConfigFile->ParseFile();
    $WPAInfo->{Valid} = $ConfigFile->{Parsed};

# use Data::Dumper;
# print Data::Dumper->Dump([$WPAInfo],[qw(WPAInfo)]);

    return $WPAInfo;
    }


########################################################################################################################
########################################################################################################################
#
# SetWPAInfo - Write wpa_supplicant info
#
# Inputs:   [Ref to] struct of WPA supplicant info
#
# Outputs:  None.
#
# NOTE: This function sets a SINGLE set of wireless credentials, using the same method
#         as raspi-config. If your application needs multiple sets, then this method
#         won't work.
#
sub SetWPAInfo {
    my $WPAInfo = shift;

    #
    # If the original file did not exist, create an original one. If needed.
    #
    return
        unless -w $WPAConfigFile;

    if( not -r $WPAConfigFile ) {

my $wpa_text = <<"END_WPA";

ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=$WPAInfo->{Country}

network={
	ssid="$WPAInfo->{SSID}"
	psk="$WPAInfo->{Password}"
    key_mgmt=$WPAInfo->{KeyMGMT}
    }
END_WPA

        write_file($WPAConfigFile,$wpa_text);
        return;
        }

    #
    # Original file exists. Reparse and add new vars as needed.
    #
    my $ConfigFile = Site::ParseData->new(Filename => $WPAConfigFile, Matches => $WPAMatches);
    $ConfigFile->ParseFile();

    return
        unless $ConfigFile->{Parsed};

    #
    # Update the existing workgroup
    #
    $ConfigFile->FromHash($WPAInfo);
    $ConfigFile->Update();
    $ConfigFile->SaveFile();

# use Data::Dumper;
# print Data::Dumper->Dump([$ConfigFile->{Lines}],[$ConfigFile->{Filename}]);

    }


########################################################################################################################
########################################################################################################################
#
# GetDHCPInfo - Return DHCPCD.conf information
#
# Inputs:   None.
#
# Outputs:  Hash of network data
#
sub GetDHCPInfo {

    return { Valid => 0 }
        unless -r $DHCPConfigFile;

    my $ConfigFile = Site::ParseData->new(Filename => $DHCPConfigFile, Matches  => $DHCPMatches);
    my $DHCPInfo   = $ConfigFile->ParseFile();
    $DHCPInfo->{Valid} = $ConfigFile->{Parsed};

# use Data::Dumper;
# print Data::Dumper->Dump([$DHCPInfo],[qw(DHCPInfo)]);

    return $DHCPInfo;
    }


########################################################################################################################
########################################################################################################################
#
# SetDHCPInfo - Set DHCPCD.conf information
#
# Inputs:   Hash of network data
#
# Outputs:  None.
#
sub SetDHCPInfo {
    my $DHCPInfo = shift;

    #
    # If the original file did not exist, we simply punt. It probably means DHCP is not installed.
    #
    return
        unless -w $DHCPConfigFile;
    
    #
    # Update the existing data
    #
    my $ConfigFile = Site::ParseData->new(Filename => $DHCPConfigFile, Matches => $DHCPMatches);
    my $OrigInfo   = $ConfigFile->ParseFile();

    return
        unless $ConfigFile->{Parsed};

    $ConfigFile->FromHash($DHCPInfo);

    #
    # Add new entries as needed, comment out the DHCP and disabled ones
    #
    foreach my $IFName (keys %{$DHCPInfo}) {

        if( !defined $OrigInfo->{$IFName}          &&
             defined $DHCPInfo->{$IFName}{IPAddr}  &&
             length  $DHCPInfo->{$IFName}{IPAddr}  &&
                     $DHCPInfo->{$IFName}{Enabled} &&
             not     $DHCPInfo->{$IFName}{DHCP}    ) {
            #
            # Add a new section to the config file.
            #
            my $IFConfig = [
                "",
                "interface $IFName",
                "    static ip_address=$DHCPInfo->{$IFName}{IPAddr}",
                "    static routers=$DHCPInfo->{$IFName}{Router}",
                "    static domain_name_servers=$DHCPInfo->{$IFName}{DNS1} $DHCPInfo->{$IFName}{DNS2}",
                ""];

            $ConfigFile->AddLines($IFConfig);
            next;
            }

        #
        # An original DHCP block exists and New description is disabled. Comment out original
        #
        if( not $DHCPInfo->{$IFName}{Enabled} ) {
            $ConfigFile->CommentSection($IFName);
            next;
            }

        #
        # An original DHCP block exists and New description is not static. Comment out original
        #
        if( $DHCPInfo->{$IFName}{DHCP} ) {
            $ConfigFile->CommentSection($IFName);
            next;
            }
        }

    $ConfigFile->Update();          # Make the changes
    $ConfigFile->SaveFile();        # Save the new file

# use Data::Dumper;
# print Data::Dumper->Dump([$ConfigFile],[$ConfigFile->{Filename}]);

    }


########################################################################################################################
########################################################################################################################
#
# GetNetEnable - Return parsed contents of netenable file
#
# Inputs:   None.
#
# Outputs:  Hash of network data
#
sub GetNetEnable {

    return { Valid => 0 }
        unless -r $NEConfigFile;

    my $ConfigFile = Site::ParseData->new(Filename => $NEConfigFile, Matches  => $NEMatches);
    my $NEInfo     = $ConfigFile->ParseFile();
    $NEInfo->{Valid} = $ConfigFile->{Parsed};

# use Data::Dumper;
# print Data::Dumper->Dump([$NEInfo],["NEInfo"]);

    return $NEInfo;
    }


########################################################################################################################
########################################################################################################################
#
# SetNetEnable - Set enable flags for known interfaces
#
# Inputs:   Hash of enable data
#
# Outputs:  None.
#
sub SetNetEnable {
    my $EnbInfo  = shift;

    #
    # If the original file did not exist, create an empty one.
    #
    unless( -w $NEConfigFile ) {
        write_file($NEConfigFile,"");
        }

    my $ConfigFile = Site::ParseData->new(Filename => $NEConfigFile, Matches => $NEMatches);
    my $NEInfo     = $ConfigFile->ParseFile();

    #
    # Update the existing vars, and add new vars as needed
    #
    foreach my $IFName (keys %{$EnbInfo}) {

        next
            unless ref($EnbInfo->{$IFName}) eq "HASH" and
                   defined $EnbInfo->{$IFName}{Enabled};

        my $Enable = $EnbInfo->{$IFName}{Enabled} ? "enable" : "disable";

        if( defined $NEInfo->{$IFName} ) {
            $ConfigFile->{Sections}{Global}{Vars}{$IFName}{NewValue} = $Enable;
            }
        else {
            $ConfigFile->AddLines("$IFName: " . $Enable);
            }
        }

    $ConfigFile->Update();
    $ConfigFile->SaveFile();

#use Data::Dumper;
#print Data::Dumper->Dump([$ConfigFile->{Lines}],[$ConfigFile->{Filename}]);

    }



#
# Perl requires that a package file return a TRUE as a final value.
#
1;
