#!/bin/bash

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Function to display error messages
function error_exit {
    echo "Error: $1" >&2
    exit 1
}

echo "Starting Resilio Sync installation on Ubuntu..."

# 1. Add Resilio Sync repository key
echo "Adding Resilio Sync repository key..."
wget -qO - https://download-cdn.resilio.com/key/resilio-sync.asc | apt-key add - || error_exit "Failed to add repository key."

# 2. Add Resilio Sync repository to sources.list.d
echo "Adding Resilio Sync repository to sources.list.d..."
echo "deb https://download-cdn.resilio.com/linux/deb resilio-sync non-free" | tee /etc/apt/sources.list.d/resilio-sync.list || error_exit "Failed to add repository."

# 3. Update package list
echo "Updating package list..."
apt update || error_exit "Failed to update package list."

# 4. Install Resilio Sync
echo "Installing Resilio Sync..."
apt install resilio-sync -y || error_exit "Failed to install Resilio Sync."

# 5. Enable and start Resilio Sync service
echo "Enabling and starting Resilio Sync service..."
systemctl enable resilio-sync || error_exit "Failed to enable Resilio Sync service."
systemctl start resilio-sync || error_exit "Failed to start Resilio Sync service."

# 6. Adjust firewall if ufw is active
if systemctl is-active --quiet ufw; then
    echo "UFW firewall detected. Opening port 8888 for Resilio Sync web UI..."
    ufw allow 8888/tcp comment 'Resilio Sync Web UI' || error_exit "Failed to open port 8888 in UFW."
    echo "UFW firewall detected. Opening UPnP port (dynamic) for Resilio Sync. Please check your Resilio Sync settings for the actual port used if you encounter connection issues."
    # Resilio Sync's actual listening port can vary or use UPnP.
    # For a more robust solution, you might need to find the listening port from Resilio Sync's configuration or logs.
    # For now, we'll assume it will try to use a dynamic port or UPnP.
    # You might need to manually add other ports if UPnP is not used or blocked.
fi

echo "Resilio Sync installation complete!"
echo "You can access the Resilio Sync web UI at: http://YOUR_SERVER_IP:8888"
echo "Please remember to replace YOUR_SERVER_IP with your actual server's IP address."
echo "You can also check the service status with: systemctl status resilio-sync"
