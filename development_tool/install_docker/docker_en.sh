#!/bin/bash

# Check if the script is run as root or with sudo privileges
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
        echo "⏭ Skipping uninstallation."
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

# Try installing Docker (official repository)
echo "⚙️  Attempting to install Docker (official repository)..."
sudo apt update
if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
    echo "✅ Docker successfully installed! (Official Repository)"
    docker --version
else
    echo "❌ Installation failed from the official repository! Switching to a domestic mirror..."

    # Choose a domestic mirror
    echo "Select a domestic mirror:"
    echo "1) Alibaba Cloud"
    echo "2) Tsinghua University"
    read -p "Enter choice (1/2): " source_choice

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
        echo "❌ Invalid selection. Exiting script."
        exit 1
    fi

    # Update package index again
    echo "🔄 Updating package index..."
    sudo apt update

    # Retry installing Docker
    echo "⚙️  Attempting to install Docker (Domestic Mirror)..."
    if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
        echo "✅ Docker successfully installed! (Domestic Mirror)"
        docker --version
    else
        echo "❌ Docker installation failed. Please check the error logs."
        exit 1
    fi
fi

configure_docker_proxy() {
    echo "🌍 Please enter Docker mirror accelerator addresses (separate multiple addresses with spaces, e.g., https://registry.docker-cn.com https://mirror.ccs.tencentyun.com). Press Enter to skip: "
    read -r proxy_urls
    if [[ -z "$proxy_urls" ]]; then
        echo "⏭ Skipping proxy configuration."
        return 0
    fi

    # Check for jq tool
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

    # Convert entered proxy addresses into JSON array format
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

    # Verify configuration
    echo "✅ Verifying configuration..."
    if sudo docker info 2>/dev/null | grep -q "$(echo "$proxy_urls" | awk '{print $1}')"; then
        echo "✅ Proxy configuration successfully applied!"
    else
        echo "❌ Proxy configuration may not have taken effect. Please check the following:"
        echo "1. Ensure the entered mirror addresses are correct."
        echo "2. Manually run 'sudo docker info' to check Registry Mirrors."
        echo "3. Check the contents and permissions of /etc/docker/daemon.json."
    fi
}

# Ask user whether to configure mirror accelerator
read -p "Do you want to configure a Docker mirror accelerator? (y/N): " configure_proxy
if [[ "$configure_proxy" =~ ^[Yy]$ ]]; then
    configure_docker_proxy
else
    echo "⏭ Skipping mirror accelerator configuration."
fi

echo "🎉 Docker installation and configuration completed!"
exit 0
