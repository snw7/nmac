#!/bin/zsh

# This script is written by snw7 and licensed under MIT License.

# Check if script has sudo privileges
if [ "$EUID" -ne 0 ]; then
    echo "\nThis script requires sudo privileges. Please run with sudo.\n"
    exit 1
fi

# Load config
readonly CURRENT_PATH="$(dirname "$0")"
path_to_config="$CURRENT_PATH/.config"

if [ ! -f "$path_to_config" ]; then
	printf "\nThe config file doesn't exist. Please update the path in the script.\n\n"
	exit 1
fi

readonly PRESET_MAC=$(awk -F'=' '/^preset_mac=/ { print $2}' $path_to_config)
readonly PRESET_HOST=$(awk -F'=' '/^preset_host=/ { print $2}' $path_to_config)

readonly ORIGINAL_MAC=$(awk -F'=' '/^original_mac=/ { print $2}' $path_to_config)
readonly ORIGINAL_HOST=$(awk -F'=' '/^original_host=/ { print $2}' $path_to_config)

readonly HOSTLIST="$CURRENT_PATH/$(awk -F'=' '/^hostlist=/ { print $2}' $path_to_config)"
readonly VENDORLIST="$CURRENT_PATH/$(awk -F'=' '/^vendorlist=/ { print $2}' $path_to_config)"

if [[ ! -n $PRESET_MAC ]] || [[ ! -n $PRESET_HOST ]] || [[ ! -n $ORIGINAL_MAC ]] || [[ ! -n $ORIGINAL_HOST ]];then
    echo "\nERROR: Your .config file is incomplete. Please check for missing values.\nTERMINATING\n"
    exit 1
fi

if [[ $HOSTLIST == $CURRENT_PATH"/" ]] || [[ ! -f $HOSTLIST ]];then
    echo "\nERROR: Hostlist file is missing. Please add it to your .config file and save it to the defined relative path.\nTERMINATING\n"
    exit 1
fi

if [[ $VENDORLIST == $CURRENT_PATH"/" ]] || [[ ! -f $VENDORLIST ]];then
    echo "\nERROR: Vendorlist file is missing. Please add it to your .config file and save it to the defined relative path.\nTERMINATING\n"
    exit 1
fi

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
    echo '\nnmac 1.1\nType "-h" for more information.\n'
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

    -p                add to other option for \"in_public\" mode - f.E. (-np)

    
    For mode '-m' save a file with hostnames as 'hostlist.txt' to the directory defined in your .config file.\n"
    exit 1
fi

if [[ ! $option ]];then
    echo '\nERROR: No option defined.\nTERMINATING\n'
    exit 1
fi

## GENERATE MAC address
vendor_name="-"

if [[ $option == 'n' ]] || [[ $option == 'm' ]];then
    vendor=$(shuf -n 1 $VENDORLIST)
    vendor_prefix=$(echo $vendor | cut -d ',' -f1)
    vendor_name=$(echo "$vendor" | awk -F ',' '{if ($2 ~ /^".*"$/) {gsub(/"/, "", $2); print $2} else {print $2}}'|sed 's/^"//')

    vendor_second_half=",$(echo "$vendor" | awk -F '"' '{print $2}' | awk -F ',' '{print $2}')"
    if [[ $vendor_second_half != "," ]]; then
        vendor_name="$vendor_name$vendor_second_half"
    fi

    random_mac=$(openssl rand -hex 4 | sed 's/\(..\)/\1:/g; s/.$//')
    max_length=$((17 - ${#vendor_prefix}))
    mac="${vendor_prefix}${random_mac: -$max_length}"
elif [[ $option == 's' ]] || [[ $option == 'd' ]] || [[ $option == 'r' ]];then
    mac=$arg_mac
fi

## COMPUTE HOSTNAME
if [[ $option == 'm' ]];then
    # fetch random from file
    arg_host=$(shuf -n 1 $HOSTLIST)
fi

if [[ $option == 'n' ]];then
    newHostname="PC-${mac[-17,-1]//[:]/-}"
fi

if [[ $option == 's' ]] || [[ $option == 'd' ]]|| [[ $option == 'm' ]] || [[ $option == 'r' ]];then
    newHostname=$arg_host
fi

## GET old IP, MAC
ip_address_old=$(ifconfig en0 | awk '/inet / {print $2}') # ipconfig getifaddr en0
mac_address_old=$(ifconfig en0 | grep ether)


###
# Start network activity
###

ssid=$(sudo wdutil info|awk -F': ' '/ SSID/{print $2}')

if [[ $(sudo wdutil info | grep -A 2 "MAC Address" | awk -F': ' '/Power/{print $2}') == "Off [Off]" ]]; then
    previous_wifi_state="down";
else
    previous_wifi_state="up";
fi

networksetup -setairportpower en0 off
networksetup -setairportpower en0 on 
sudo ifconfig en0 up

# CHANGE mac
sudo ifconfig en0 ether $mac

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

if [[ $previous_wifi_state == "up" ]] && [[ $ssid != "None" ]]; then
    # reconnect to wifi
    for count in {0..15}; do
        # initiate reconnect every 7s
        if [[ $count -eq 0 || $((count % 8)) -eq 0 ]]; then
            networksetup -setairportnetwork en0 $ssid> /dev/null
        fi

        ip_address_new=$(ifconfig en0 | awk '/inet / {print $2}')

        # terminate when new IP is read or waiting time exceeds 15s
        if [[ -n "${ip_address_new// }" ]]; then
            break
        fi

        sleep 1
    done

    new_ssid=$(sudo wdutil info|awk -F': ' '/ SSID/{print $2}')

    if [[ $new_ssid != "None" ]]; then
        state="Reconnected to: $new_ssid\n"
    else
        state="Failed to reconnect to: $ssid\n"
    fi
else
    # disable wifi for enhanced privacy
    networksetup -setairportpower en0 off
fi

###
# PRINT changes
###

hostname=$(hostname)

if [[ $mac_address_new != $mac_address_old ]]; then
    mac_changed="true"
fi

if [[ $mac_changed != "true" ]]; then
    vendor_name="-"
fi

if [[ $in_public == "true" ]]; then
    mac_address_old="00:00:00:00:00:00"
    mac_address_new="00:00:00:00:00:00"
    ip_address_old="0.0.0.0"
    ip_address_new="0.0.0.0"
    hostname="-"
    vendor_name="-"
fi

echo "\nnew HOSTNAME: $hostname"

echo "\nold MAC: ${mac_address_old[-17,-1]}" # -18, -2 (before macOS SONOMA)
echo "new MAC: ${mac_address_new[-17,-1]}"

if [[ $mac_changed == "true" ]] && [[ $in_public == "true" ]]; then
    echo "-> changed"
fi

echo "\nVendor: $vendor_name\n"

if [[ $ssid != 'None' ]]; then
    echo "old IP: ${ip_address_old}"
    echo "new IP: ${ip_address_new}\n"
fi

if [[ -n $state ]]; then
    echo $state;
fi

if [[ $option == 'n' ]] || [[ $option == 'm' ]];then
    echo "Identity switched.\n"
elif [[ $option == 'r' ]];then
    echo "Identity reset.\n"
elif [[ $option == 's' ]] || [[ $option == 'd' ]];then
    echo "Identity cloned.\n"
fi
