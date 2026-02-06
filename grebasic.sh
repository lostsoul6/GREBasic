#!/bin/bash

# Script to create/remove basic GRE tunnel between Iran and Kharej servers
# No NAT, no iptables forwarding rules — just the tunnel itself

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Function to validate IPv4 address
validate_ipv4() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 || $octet -lt 0 ]]; then
                echo "Invalid IPv4 address: $ip"
                return 1
            fi
        done
        return 0
    else
        echo "Invalid IPv4 address format: $ip"
        return 1
    fi
}

# Function to create /etc/rc.local for Iran Server (tunnel only)
create_rc_local_iran() {
    local iran_ipv4=$1
    local kharej_ipv4=$2
    echo "Creating /etc/rc.local for Iran Server (GRE tunnel only)..."
    cat > /etc/rc.local << EOF
#!/bin/bash

# Enable IPv4 forwarding (optional but commonly wanted)
sysctl -w net.ipv4.conf.all.forwarding=1

# Load GRE module if not already loaded
modprobe ip_gre 2>/dev/null || true

# Create GRE tunnel
ip tunnel add gre1 mode gre remote $kharej_ipv4 local $iran_ipv4 ttl 255
ip addr add 172.16.1.1/30 dev gre1
ip link set gre1 mtu 1420
ip link set gre1 up

exit 0
EOF
    chmod +x /etc/rc.local
    echo "/etc/rc.local created and made executable."
    echo "Applying changes immediately..."
    if bash /etc/rc.local; then
        echo "GRE tunnel created successfully on Iran side."
    else
        echo "Error: Failed to apply tunnel configuration."
        exit 1
    fi
}

# Function to create /etc/rc.local for Kharej Server (tunnel only)
create_rc_local_kharej() {
    local kharej_ipv4=$1
    local iran_ipv4=$2
    echo "Creating /etc/rc.local for Kharej Server (GRE tunnel only)..."
    cat > /etc/rc.local << EOF
#!/bin/bash

# Enable IPv4 forwarding (optional but commonly wanted)
sysctl -w net.ipv4.conf.all.forwarding=1

# Load GRE module if not already loaded
modprobe ip_gre 2>/dev/null || true

# Create GRE tunnel
ip tunnel add gre1 mode gre remote $iran_ipv4 local $kharej_ipv4 ttl 255
ip addr add 172.16.1.2/30 dev gre1
ip link set gre1 mtu 1420
ip link set gre1 up

exit 0
EOF
    chmod +x /etc/rc.local
    echo "/etc/rc.local created and made executable."
    echo "Applying changes immediately..."
    if bash /etc/rc.local; then
        echo "GRE tunnel created successfully on Kharej side."
    else
        echo "Error: Failed to apply tunnel configuration."
        exit 1
    fi
}

# Function to remove the GRE tunnel
remove_tunnel() {
    echo "Removing GRE tunnel..."
    
    # Bring down and delete the tunnel
    ip link set gre1 down 2>/dev/null
    ip tunnel del gre1 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        echo "GRE tunnel (gre1) removed successfully."
    else
        echo "No GRE tunnel named 'gre1' found or already removed."
    fi
    
    # Remove /etc/rc.local if it exists
    if [[ -f /etc/rc.local ]]; then
        echo "Removing /etc/rc.local..."
        rm -f /etc/rc.local
        echo "/etc/rc.local removed."
    else
        echo "No /etc/rc.local file found."
    fi
    
    echo "Cleanup completed."
}

# ------------------------------------------------
echo "Select an option:"
echo "1) Configure Iran Server (create GRE tunnel)"
echo "2) Configure Kharej Server (create GRE tunnel)"
echo "3) Remove GRE tunnel"
echo ""
read -p "Enter choice (1, 2, or 3): " choice

case "$choice" in
    1)
        echo "Configuring Iran Server (tunnel only)..."
        read -p "Enter Iran Server Public IPv4: " iran_ipv4
        if ! validate_ipv4 "$iran_ipv4"; then exit 1; fi
        
        read -p "Enter Kharej Server Public IPv4: " kharej_ipv4
        if ! validate_ipv4 "$kharej_ipv4"; then exit 1; fi
        
        create_rc_local_iran "$iran_ipv4" "$kharej_ipv4"
        ;;
    2)
        echo "Configuring Kharej Server (tunnel only)..."
        read -p "Enter Kharej Server Public IPv4: " kharej_ipv4
        if ! validate_ipv4 "$kharej_ipv4"; then exit 1; fi
        
        read -p "Enter Iran Server Public IPv4: " iran_ipv4
        if ! validate_ipv4 "$iran_ipv4"; then exit 1; fi
        
        create_rc_local_kharej "$kharej_ipv4" "$iran_ipv4"
        ;;
    3)
        remove_tunnel
        ;;
    *)
        echo "Invalid choice. Please select 1, 2, or 3."
        exit 1
        ;;
esac

echo ""
echo "Done."
exit 0
