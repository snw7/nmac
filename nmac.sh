#!/bin/zsh

# This script is licensed under MIT License.

# Check if script has sudo privileges
if [ "$EUID" -ne 0 ]; then
    echo "\nThis script requires sudo privileges. Please run with sudo.\n"
    exit 1
fi

# Get config
readonly CURRENT_PATH=$(pwd)
path_to_config="$CURRENT_PATH/.config"

# check if the user passed in the config file and that the file exists
if [ ! -f "$path_to_config" ]; then
	printf "\nThe config file doesn't exist. Please update the path in the script.\n\n"
	exit 1
fi

readonly PRESET_MAC=$(awk -F'=' '/^preset_mac=/ { print $2}' $path_to_config)
readonly PRESET_HOST=$(awk -F'=' '/^preset_host=/ { print $2}' $path_to_config)

readonly ORIGINAL_MAC=$(awk -F'=' '/^original_mac=/ { print $2}' $path_to_config)
readonly ORIGINAL_HOST=$(awk -F'=' '/^original_host=/ { print $2}' $path_to_config)

# Parse options
while getopts ":nrphmds:" opt; do
    case $opt in
        n)
            option='n'
            ;;
        r)
            arg_mac="$ORIGINAL_MAC"
            arg_host="$ORIGINAL_HOST"
            option='r'
            ;;
        m)
            option='m'
            ;;
        s)
            arg_mac="$OPTARG"
            shift 1
            arg_host="$2"
            shift 1
            option='s'
            ;;
        d)
            arg_mac="$PRESET_MAC"
            arg_host="$PRESET_HOST"
            option='d'
            ;;
        h)
            option='h'
            ;;
        p)
            # dont echo mac and ip
            in_public="true"
            ;;
        *)
            echo "Invalid option: -$OPTARG"
            exit 1
            ;;
    esac
done

if [[ $# -eq 0 ]]; then
    echo '\nnmac 1.0\nType "-h" for more information.\n'
    exit 1
fi

# Help
if [[ $option == 'h' ]];then
    echo "    written by snw7 (08/2023)
    
    this programm is used to change MAC, IP and HOSTNAME of a device.
    
    OPTIONS:
    -h                get this help menu
    -d                change IP, MAC and HOSTNAME to preset device
    -m                stealth mode - set to realistic consumer host
    -n                change IP, MAC and HOSTNAME to random
    -r                change IP, MAC and HOSTNAME to original
    -s MAC HOSTNAME   set MAC and HOSTNAME to custom values

    -p                add for "in_public" mode

    
    For mode '-m' save a file with hostnames as 'hostlist.txt' to the directory defined in your .config file."
    exit 1
fi

## GENERATE MAC address
# -> avoid generating a multicast address (set first two chars)
if [[ $option == 'n' ]] || [[ $option == 'm' ]];then
    mac=$(openssl rand -hex 5 | sed 's/\(..\)/\1:/g; s/.$//')
    mac="00:$mac"
elif [[ $option == 's' ]] || [[ $option == 'd' ]] || [[ $option == 'r' ]];then
    mac=$arg_mac
else
    echo 'ERROR: no option defined (MAC)\nTERMINATING'
    exit 1
fi

## COMPUTE HOSTNAME
if [[ $option == 'm' ]];then
    # fetch random from file
    arg_host=$(shuf -n 1 ~/path/to/file/hostlist.txt)
fi

if [[ $option == 'n' ]];then
    newHostname="PC-${mac[-17,-1]//[:]/-}"
fi

if [[ $option == 's' ]] || [[ $option == 'd' ]]|| [[ $option == 'm' ]] || [[ $option == 'r' ]];then
    newHostname=$arg_host
fi

if [[ ! $option ]];then
    echo 'ERROR: no option defined (HOSTNAME)\nTERMINATING'
    exit 1
fi

## GET old IP, MAC
ip_address_old=$(ifconfig en0 | awk '/inet / {print $2}') # ipconfig getifaddr en0
mac_address_old=$(ifconfig en0 | grep ether)


###
# Start network activity
###

ssid=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | awk -F': ' '/ SSID/{print $2}')

if [[ $(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I) == "AirPort: Off" ]]; then
    wifiState="down";
    networksetup -setairportpower en0 on 
    sudo ifconfig en0 up
else
    wifiState="up";
fi

# CHANGE mac
sudo /opt/homebrew/bin/spoof-mac set $mac en0

# GET new MAC
mac_address_new=$(ifconfig en0 | grep ether)

# change HOSTNAME
sudo scutil --set ComputerName $newHostname
sudo scutil --set HostName $newHostname
sudo scutil --set LocalHostName $newHostname
dscacheutil -flushcache

# reset IPv4
sudo ipconfig set en0 DHCP
sudo ipconfig set en0 BOOTP

#reset IPv6
sudo networksetup -setv6off Wi-Fi
sudo networksetup -setv6automatic Wi-Fi

if [[ $wifiState == "up" ]] && [[ $ssid != "" ]]; then
    # reconnect to wifi
    if [[ -n "${ssid// }" ]]; then
        networksetup -setairportnetwork en0 $ssid> /dev/null
        state="Reconnected to: $ssid"
    else
        state="Finished."
    fi
    
    # wait for new IP
    count=0
    condition_met=false

    while [[ "$condition_met" != true ]]; do
        ((count++)) 
        ip_address_new=$(ifconfig en0 | awk '/inet / {print $2}')

        # terminate when new IP is read or waiting time exceeds 15s
        if [[ -n "${ip_address_new// }" ]] || ((count > 15)); then
            condition_met=true
        fi

        # retry connection
        if (( count == 8 )); then
            networksetup -setairportnetwork en0 $ssid> /dev/null
        fi

        sleep 1
    done
else
    # disable wifi for enhanced privacy
    networksetup -setairportpower en0 off
fi


# PRINT changes

hostname=$(hostname)

if [[ $in_public == "true" ]]; then
    if [[ $mac_address_new != $mac_address_old ]]; then
        mac_changed="true"
    fi

    mac_address_old="00:00:00:00:00:00"
    mac_address_new="00:00:00:00:00:00"
    ip_address_old="0.0.0.0"
    ip_address_new="0.0.0.0"
    hostname="-"
fi

echo "\nnew HOSTNAME: $hostname"

echo "\nold MAC: ${mac_address_old[-17,-1]}" # -18, -2 (before macOS SONOMA)
echo "new MAC: ${mac_address_new[-17,-1]}"

if [[ $mac_changed == "true" ]]; then
    echo "-> changed"
fi

if [[ $ssid != "" ]]; then
    echo "\nold IP: ${ip_address_old}"
    echo "new IP: ${ip_address_new}\n"
fi

echo $state;

if [[ $option == 'n' ]] || [[ $option == 'm' ]];then
    echo "Identity switched.\n"
elif [[ $option == 'r' ]];then
    echo "Identity reset.\n"
elif [[ $option == 's' ]] || [[ $option == 'd' ]];then
    echo "Identity cloned.\n"
fi