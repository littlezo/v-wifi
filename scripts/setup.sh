#!/bin/bash
set -e

# Default variables (can be overridden by environment)
WIFI_IFACE="${WIFI_IFACE:-wlp3s0}"
ETH_IFACE="${ETH_IFACE:-enp3s0}"
AP_SUBNET="${AP_SUBNET:-192.168.8.0/24}"
AP_GATEWAY="${AP_GATEWAY:-192.168.8.1}"
SSID="${SSID:-meta}"
PASSWORD="${PASSWORD:-meta.2025}"
BAND="${BAND:-5}"  # options: 2.4 or 5 - Default to 5GHz for better AC/AX performance
CHANNEL="${CHANNEL:-44}"
HW_MODE="${HW_MODE:-a}"

# Auto-detect WiFi hardware capabilities and set appropriate mode
# Default settings based on BAND
if [ "$BAND" = "5" ]; then
    CHANNEL="a"
else
    CHANNEL="g"
fi

# Initialize capability flags with default values
EHT_CAPABLE="false"
HE_CAPABLE="false"
VHT_CAPABLE="false"
HT_CAPABLE="false"

# Initialize bandwidth capabilities
MAX_BANDWIDTH="20"  # Default to 20MHz
SUPPORTED_BANDWIDTHS="20"
phy_name=$(iw dev "$WIFI_IFACE" info 2> /dev/null | grep -o 'wiphy [0-9]\+' | cut -d ' ' -f 2) 
# Check if WiFi interface exists and get its capabilities
if command -v iw &> /dev/null && ip link show "$WIFI_IFACE" &> /dev/null; then
    echo "Checking WiFi hardware capabilities for $WIFI_IFACE..."
    
    # Get detailed hardware capabilities using phy info
    if iw phy"$phy_name" info &> /dev/null; then
        IW_INFO=$(iw phy"$phy_name" info)
        
        # Check for EHT (802.11be) capabilities
        if echo "$IW_INFO" | grep -qi "EHT"; then
            EHT_CAPABLE="true"
            echo "WiFi 7 (802.11be) capability detected."
        fi
        
        # Check for HE (802.11ax) capabilities - more precise detection
        if echo "$IW_INFO" | grep -qi "HE Iftypes.*AP"; then
            HE_CAPABLE="true"
            echo "WiFi 6 (802.11ax) capability detected."
        fi
        
        # Check for VHT (802.11ac) capabilities
        if echo "$IW_INFO" | grep -qi "VHT Capabilities"; then
            VHT_CAPABLE="true"
            echo "WiFi 5 (802.11ac) capability detected."
        fi
        
        # Check for HT (802.11n) capabilities
        if echo "$IW_INFO" | grep -qi "HT20/HT40"; then
            HT_CAPABLE="true"
            echo "WiFi 4 (802.11n) capability detected."
        fi
        
        # Detect maximum supported bandwidth with more precise detection
        if echo "$IW_INFO" | grep -qi "HE80.*5GHz"; then
            MAX_BANDWIDTH="80"
            SUPPORTED_BANDWIDTHS="20 40 80"
            echo "80MHz bandwidth capability detected (HE80 in 5GHz)."
        elif echo "$IW_INFO" | grep -qi "HE40.*5GHz"; then
            MAX_BANDWIDTH="40"
            SUPPORTED_BANDWIDTHS="20 40"
            echo "40MHz bandwidth capability detected (HE40 in 5GHz)."
        elif echo "$IW_INFO" | grep -qi "VHT80"; then
            MAX_BANDWIDTH="80"
            SUPPORTED_BANDWIDTHS="20 40 80"
            echo "80MHz bandwidth capability detected (VHT80)."
        elif echo "$IW_INFO" | grep -qi "HT40"; then
            MAX_BANDWIDTH="40"
            SUPPORTED_BANDWIDTHS="20 40"
            echo "40MHz bandwidth capability detected (HT40)."
        else
            MAX_BANDWIDTH="20"
            SUPPORTED_BANDWIDTHS="20"
            echo "Defaulting to 20MHz bandwidth."
        fi
        
    else
        echo "Warning: iw phy${phy_name} info command failed. Trying alternative detection methods."
        # Fallback to interface-specific detection
        if iw list dev "$WIFI_IFACE" &> /dev/null; then
            IW_INFO=$(iw list dev "$WIFI_IFACE")
            
            # Fallback detection logic
            if echo "$IW_INFO" | grep -qi "HE"; then
                HE_CAPABLE="true"
                echo "WiFi 6 (802.11ax) capability detected (fallback)."
            fi
            
            if echo "$IW_INFO" | grep -qi "VHT"; then
                VHT_CAPABLE="true"
                echo "WiFi 5 (802.11ac) capability detected (fallback)."
            fi
            
            if echo "$IW_INFO" | grep -qi "HT"; then
                HT_CAPABLE="true"
                echo "WiFi 4 (802.11n) capability detected (fallback)."
            fi
            
            # Fallback bandwidth detection
            if echo "$IW_INFO" | grep -qi "80 MHz"; then
                MAX_BANDWIDTH="80"
                SUPPORTED_BANDWIDTHS="20 40 80"
                echo "80MHz bandwidth capability detected (fallback)."
            elif echo "$IW_INFO" | grep -qi "40 MHz"; then
                MAX_BANDWIDTH="40"
                SUPPORTED_BANDWIDTHS="20 40"
                echo "40MHz bandwidth capability detected (fallback)."
            else
                MAX_BANDWIDTH="20"
                SUPPORTED_BANDWIDTHS="20"
                echo "Defaulting to 20MHz bandwidth (fallback)."
            fi
        else
            echo "Warning: All hardware detection methods failed. Using default capabilities."
        fi
    fi
    export SUPPORTED_BANDWIDTHS
    # Determine optimal mode based on capabilities (priority: EHT > HE > VHT > HT > Basic)
    if [ "$EHT_CAPABLE" = "true" ]; then
        echo "Using WiFi 7 (802.11be) mode with maximum bandwidth optimization."
        HW_MODE="a"
        CHANNEL="36"  # Use channel 36 for better stability
    elif [ "$HE_CAPABLE" = "true" ]; then
        echo "Using WiFi 6 (802.11ax) mode with bandwidth optimization."
        HW_MODE="a"
        CHANNEL="36"  # Use channel 36 for better stability
    elif [ "$VHT_CAPABLE" = "true" ]; then
        echo "Using WiFi 5 (802.11ac) mode."
        HW_MODE="a"
        CHANNEL="36"  # Use channel 36 for better stability
    elif [ "$HT_CAPABLE" = "true" ]; then
        echo "Using WiFi 4 (802.11n) mode."
        HW_MODE="$DEFAULT_HW_MODE"
        CHANNEL="36"  # Use channel 36 for better stability
    else
        echo "No advanced WiFi capabilities detected. Using basic mode."
        HW_MODE="$DEFAULT_HW_MODE"
        CHANNEL="36"  # Use channel 36 for better stability
    fi
else
    echo "Could not check WiFi capabilities. Using default settings."
    # When iw list fails, disable all advanced capabilities to avoid configuration errors
    EHT_CAPABLE="false"
    HE_CAPABLE="false"
    VHT_CAPABLE="false"
    HT_CAPABLE="false"
    MAX_BANDWIDTH="20"
fi

echo "Selected mode: $HW_MODE, channel: $CHANNEL, max bandwidth: ${MAX_BANDWIDTH}MHz"

# Set regulatory domain BEFORE touching the interface
iw reg set GB

# Bring interface down/up AFTER reg domain is set
ip link set dev "$WIFI_IFACE" down
ip link set dev "$WIFI_IFACE" up

# Generate hostapd.conf with dynamic settings based on hardware capabilities
# First, create the base configuration
cat > /etc/hostapd/hostapd.conf <<EOF
country_code=GB
interface=${WIFI_IFACE}
driver=nl80211
ssid=${SSID}
hw_mode=${HW_MODE}
channel=${CHANNEL}
#ieee80211d=1
EOF

# Configure bandwidth settings based on detected maximum bandwidth and supported standards
case "$MAX_BANDWIDTH" in
    "320")
        echo "# 320MHz bandwidth configuration" >> /etc/hostapd/hostapd.conf
        if [ "$VHT_CAPABLE" = "true" ]; then
            echo "vht_oper_chwidth=2" >> /etc/hostapd/hostapd.conf
            echo "vht_oper_centr_freq_seg0_idx=42" >> /etc/hostapd/hostapd.conf
        fi
        if [ "$HE_CAPABLE" = "true" ]; then
            echo "he_oper_chwidth=2" >> /etc/hostapd/hostapd.conf
            echo "he_oper_centr_freq_seg0_idx=42" >> /etc/hostapd/hostapd.conf
        fi
        # EHT configuration disabled due to hostapd v2.10 incompatibility
        # if [ "$EHT_CAPABLE" = "true" ]; then
        #     echo "eht_oper_chwidth=2" >> /etc/hostapd/hostapd.conf
        #     echo "eht_oper_centr_freq_seg0_idx=42" >> /etc/hostapd/hostapd.conf
        # fi
        ;;
    "160")
        echo "# 160MHz bandwidth configuration" >> /etc/hostapd/hostapd.conf
        if [ "$VHT_CAPABLE" = "true" ]; then
            echo "vht_oper_chwidth=2" >> /etc/hostapd/hostapd.conf
            echo "vht_oper_centr_freq_seg0_idx=42" >> /etc/hostapd/hostapd.conf
        fi
        if [ "$HE_CAPABLE" = "true" ]; then
            echo "he_oper_chwidth=2" >> /etc/hostapd/hostapd.conf
            echo "he_oper_centr_freq_seg0_idx=42" >> /etc/hostapd/hostapd.conf
        fi
        # EHT configuration disabled due to hostapd v2.10 incompatibility
        # if [ "$EHT_CAPABLE" = "true" ]; then
        #     echo "eht_oper_chwidth=2" >> /etc/hostapd/hostapd.conf
        #     echo "eht_oper_centr_freq_seg0_idx=42" >> /etc/hostapd/hostapd.conf
        # fi
        ;;
    "80")
        echo "# 80MHz bandwidth configuration" >> /etc/hostapd/hostapd.conf
        if [ "$VHT_CAPABLE" = "true" ]; then
            echo "vht_oper_chwidth=1" >> /etc/hostapd/hostapd.conf
            echo "vht_oper_centr_freq_seg0_idx=42" >> /etc/hostapd/hostapd.conf
        fi
        if [ "$HE_CAPABLE" = "true" ]; then
            echo "he_oper_chwidth=1" >> /etc/hostapd/hostapd.conf
            echo "he_oper_centr_freq_seg0_idx=42" >> /etc/hostapd/hostapd.conf
        fi
        # EHT configuration disabled due to hostapd v2.10 incompatibility
        # if [ "$EHT_CAPABLE" = "true" ]; then
        #     echo "eht_oper_chwidth=1" >> /etc/hostapd/hostapd.conf
        #     echo "eht_oper_centr_freq_seg0_idx=42" >> /etc/hostapd/hostapd.conf
        # fi
        
        # Add bandwidth fallback support for better compatibility
        echo "he_basic_mcs_nss_set=0xfffc" >> /etc/hostapd/hostapd.conf
        # Relax requirements for better compatibility with various clients
        echo "#require_ht=1" >> /etc/hostapd/hostapd.conf
        echo "#require_vht=1" >> /etc/hostapd/hostapd.conf
        echo "#require_he=1" >> /etc/hostapd/hostapd.conf
        # Realtek-specific optimizations (commented out due to hostapd v2.10 incompatibility)
        # echo "ignore_40_mhz_intolerant=1" >> /etc/hostapd/hostapd.conf
        # echo "disable_40mhz_scan=0" >> /etc/hostapd/hostapd.conf
        ;;
    "40")
        echo "# 40MHz bandwidth configuration" >> /etc/hostapd/hostapd.conf
        if [ "$VHT_CAPABLE" = "true" ]; then
            echo "vht_oper_chwidth=0" >> /etc/hostapd/hostapd.conf
        fi
        if [ "$HE_CAPABLE" = "true" ]; then
            echo "he_oper_chwidth=0" >> /etc/hostapd/hostapd.conf
        fi
        # EHT configuration disabled due to hostapd v2.10 incompatibility
        # if [ "$EHT_CAPABLE" = "true" ]; then
        #     echo "eht_oper_chwidth=0" >> /etc/hostapd/hostapd.conf
        # fi
        ;;
    *)
        echo "# 20MHz bandwidth configuration" >> /etc/hostapd/hostapd.conf
        if [ "$VHT_CAPABLE" = "true" ]; then
            echo "vht_oper_chwidth=0" >> /etc/hostapd/hostapd.conf
        fi
        if [ "$HE_CAPABLE" = "true" ]; then
            echo "he_oper_chwidth=0" >> /etc/hostapd/hostapd.conf
        fi
        # EHT configuration disabled due to hostapd v2.10 incompatibility
        # if [ "$EHT_CAPABLE" = "true" ]; then
        #     echo "eht_oper_chwidth=0" >> /etc/hostapd/hostapd.conf
        # fi
        ;;
esac

# Enable IEEE 802.11n (HT) if supported
if [ "$HT_CAPABLE" = "true" ]; then
    echo "ieee80211n=1" >> /etc/hostapd/hostapd.conf
    echo "# WiFi 4 (802.11n) HT settings" >> /etc/hostapd/hostapd.conf
    echo "ht_capab=[HT40+][LDPC][SHORT-GI-20][SHORT-GI-40][TX-STBC][RX-STBC1][MAX-AMSDU-7935]" >> /etc/hostapd/hostapd.conf
    # Add HT compatibility settings
    echo "obss_interval=1" >> /etc/hostapd/hostapd.conf
    # ht_coex parameter not supported by hostapd v2.10
    # echo "ht_coex=0" >> /etc/hostapd/hostapd.conf
    # Add connection stability optimizations
    echo "beacon_int=100" >> /etc/hostapd/hostapd.conf
    echo "dtim_period=2" >> /etc/hostapd/hostapd.conf
    echo "max_num_sta=32" >> /etc/hostapd/hostapd.conf
    echo "rts_threshold=2347" >> /etc/hostapd/hostapd.conf
    echo "fragm_threshold=2346" >> /etc/hostapd/hostapd.conf
else
    echo "#ieee80211n=0" >> /etc/hostapd/hostapd.conf
    echo "# WiFi 4 (802.11n) not supported by hardware" >> /etc/hostapd/hostapd.conf
fi

# Enable IEEE 802.11ac (VHT) if supported
if [ "$VHT_CAPABLE" = "true" ]; then
    echo "ieee80211ac=1" >> /etc/hostapd/hostapd.conf
    echo "# WiFi 5 (802.11ac) VHT settings" >> /etc/hostapd/hostapd.conf
    # vht_supported_mcs parameter not supported by hostapd v2.10
    # echo "vht_supported_mcs=\"0-9 11\"" >> /etc/hostapd/hostapd.conf
    echo "vht_capab=[MAX-MPDU-11454][RXLDPC][SHORT-GI-80][TX-STBC-2BY1][RX-STBC-1][MAX-A-MPDU-LEN-EXP7]" >> /etc/hostapd/hostapd.conf
    
    # Add VHT160 capability if bandwidth supports it
    if [ "$MAX_BANDWIDTH" = "160" ] || [ "$MAX_BANDWIDTH" = "320" ]; then
        echo "vht_capab=\$vht_capab[VHT160]" >> /etc/hostapd/hostapd.conf
    fi
else
    echo "#ieee80211ac=0" >> /etc/hostapd/hostapd.conf
    echo "# WiFi 5 (802.11ac) not supported by hardware" >> /etc/hostapd/hostapd.conf
fi

# Enable IEEE 802.11ax (HE) if supported
if [ "$HE_CAPABLE" = "true" ]; then
    echo "ieee80211ax=1" >> /etc/hostapd/hostapd.conf
    echo "# WiFi 6 (802.11ax) HE settings" >> /etc/hostapd/hostapd.conf
    echo "he_su_beamformer=1" >> /etc/hostapd/hostapd.conf
    echo "he_su_beamformee=1" >> /etc/hostapd/hostapd.conf
    echo "he_mu_beamformer=1" >> /etc/hostapd/hostapd.conf
    echo "he_bss_color=8" >> /etc/hostapd/hostapd.conf
    # he_ppe_size and he_max_aid parameters not supported by hostapd v2.10
    # echo "he_ppe_size=4096" >> /etc/hostapd/hostapd.conf
    # echo "he_max_aid=64" >> /etc/hostapd/hostapd.conf
else
    echo "#ieee80211ax=0" >> /etc/hostapd/hostapd.conf
    echo "# WiFi 6 (802.11ax) not supported by hardware" >> /etc/hostapd/hostapd.conf
fi

# Note: IEEE 802.11be (EHT/WiFi 7) is not supported by hostapd v2.10
# Disabling EHT configuration to avoid configuration errors
echo "# WiFi 7 (802.11be) not supported by hostapd v2.10" >> /etc/hostapd/hostapd.conf
echo "#ieee80211be=0" >> /etc/hostapd/hostapd.conf

# Add remaining common settings
cat >> /etc/hostapd/hostapd.conf <<EOF
wmm_enabled=1
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=${PASSWORD}
logger_syslog=-1
logger_syslog_level=1
EOF

# Generate dnsmasq.conf
cat > /etc/dnsmasq.conf <<EOF
interface=${WIFI_IFACE}
dhcp-range=${AP_GATEWAY%.*}.180,${AP_GATEWAY%.*}.239,24h
server=8.8.8.8
server=8.8.4.4
bind-interfaces
log-queries=no
EOF