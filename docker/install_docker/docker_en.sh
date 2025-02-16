#!/bin/bash

# Check if the script is executed as root or with sudo privileges
if [ "$(id -u)" != "0" ]; then
    echo "Please run this script as root or use sudo."
    exit 1
fi

echo "🚀 Starting Docker installation script..."

# Check if Docker is already installed
if command -v docker &>/dev/null; then
    echo "Docker detected: $(docker --version)"
    read -p "Do you want to uninstall the current Docker? (y/N): " remove_docker
    if [[ "$remove_docker" =~ ^[Yy]$ ]]; then
        echo "🛠 Uninstalling Docker..."
        sudo apt remove -y docker-desktop
        rm -r $HOME/.docker/desktop 2>/dev/null || echo "No residual directories to clean."
        sudo rm /usr/local/bin/com.docker.cli 2>/dev/null || echo "No residual files to clean."
        sudo apt purge -y docker-desktop docker-ce docker-ce-cli containerd.io
        sudo rm -rf /var/lib/docker /etc/docker
        echo "✅ Docker has been uninstalled."
    else
        echo "⏭ Skipping uninstallation step."
    fi
fi

# Update package index
echo "🔄 Updating package index..."
sudo apt update

# Add Docker official repository
echo "🌍 Adding Docker official repository..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Attempt to install Docker from the official repository
echo "⚙️  Attempting to install Docker (official source)..."
sudo apt update
if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
    echo "✅ Docker installed successfully! (official source)"
    docker --version
else
    echo "❌ Installation from the official source failed! Trying alternative sources..."

    # Choose a domestic mirror source
    echo "Choose a mirror source:"
    echo "1) Alibaba Cloud"
    echo "2) Tsinghua University"
    read -p "Enter your choice (1/2): " source_choice

    if [ "$source_choice" == "1" ]; then
        echo "🔄 Switching to Alibaba Cloud mirror..."
        curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository \
            "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
    elif [ "$source_choice" == "2" ]; then
        echo "🔄 Switching to Tsinghua University mirror..."
        curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository \
            "deb [arch=amd64] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
    else
        echo "❌ Invalid choice. Exiting script."
        exit 1
    fi

    # Update package index again
    echo "🔄 Updating package index..."
    sudo apt update

    # Attempt to install Docker from the selected mirror
    echo "⚙️  Attempting to install Docker (mirror source)..."
    if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
        echo "✅ Docker installed successfully! (mirror source)"
        docker --version
    else
        echo "❌ Docker installation failed. Please check the error log."
        exit 1
    fi
fi

configure_docker_proxy() {
    echo "🌍 Enter Docker registry mirror addresses (separated by spaces, e.g., https://registry.docker-cn.com https://mirror.ccs.tencentyun.com), press Enter to skip:"
    read -r proxy_urls
    if [[ -z "$proxy_urls" ]]; then
        echo "⏭ Skipping proxy configuration."
        return 0
    fi

    # Check if jq is installed
    if ! command -v jq &>/dev/null; then
        echo "🛠 Installing jq tool..."
        if ! (sudo apt install -y jq 2>/dev/null || sudo yum install -y jq 2>/dev/null || sudo dnf install -y jq 2>/dev/null || sudo pacman -S --noconfirm jq 2>/dev/null || sudo zypper install -y jq 2>/dev/null); then
            echo "❌ Failed to install jq automatically. Please install it manually and retry."
            return 1
        fi
    fi

    # Ensure /etc/docker directory exists
    sudo mkdir -p /etc/docker

    # Handle configuration file
    config_file="/etc/docker/daemon.json"
    tmp_file=$(mktemp)

    # Convert input proxy URLs to JSON array format
    registry_mirrors=()
    for url in $proxy_urls; do
        registry_mirrors+=("\"$url\"")
    done
    mirrors_json="[${registry_mirrors[*]}]"

    # Update or create daemon.json
    if [ -f "$config_file" ]; then
        jq --argjson mirrors "$mirrors_json" '."registry-mirrors" = $mirrors' "$config_file" > "$tmp_file"
    else
        echo "{\"registry-mirrors\": $mirrors_json}" | jq . > "$tmp_file"
    fi

    # Ensure target file exists
    sudo touch "$config_file"

    # Apply configuration
    sudo mv "$tmp_file" "$config_file"
    sudo chmod 600 "$config_file"

    echo "🔄 Restarting Docker service..."
    sudo systemctl restart docker

    # Validate configuration
    echo "✅ Verifying configuration..."
    if sudo docker info 2>/dev/null | grep -q "$(echo "$proxy_urls" | awk '{print $1}')"; then
        echo "✅ Proxy configuration verified successfully!"
    else
        echo "❌ Proxy configuration may not have been applied correctly. Please check the settings."
    fi
}

# Ask the user if they want to configure a Docker registry mirror
read -p "Do you want to configure a Docker registry mirror? (y/N): " configure_proxy
if [[ "$configure_proxy" =~ ^[Yy]$ ]]; then
    configure_docker_proxy
else
    echo "⏭ Skipping registry mirror configuration."
fi

# Ask the user if they want to enable Docker to start on boot
read -p "Do you want to enable Docker to start on boot? (y/N): " autostart_choice
if [[ "$autostart_choice" =~ ^[Yy]$ ]]; then
    echo "🚀 Enabling Docker to start on boot..."
    if sudo systemctl enable docker; then
        echo "✅ Docker is now set to start on boot!"
    else
        echo "❌ Failed to enable Docker startup. Please check the error log."
    fi
else
    echo "⏭ Skipping Docker startup configuration."
fi

# Ask the user if they want to install the Docker monitoring panel (dpanel)
read -p "Do you want to install the Docker monitoring panel (dpanel)? (y/N): " install_dpanel
if [[ "$install_dpanel" =~ ^[Yy]$ ]]; then
    echo "🛠 Installing Docker monitoring panel..."
    curl -sSL https://dpanel.cc/quick.sh -o quick.sh && sudo bash quick.sh
    echo "✅ Docker monitoring panel installed successfully!"
else
    echo "⏭ Skipping Docker monitoring panel installation."
fi

echo "🎉 Docker installation and configuration completed!"
exit 0
