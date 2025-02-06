#!/bin/bash

# Check if the script is run as root or with sudo privileges
if [ "$(id -u)" != "0" ]; then
    echo "Please run this script as root or with sudo."
    exit 1
fi

echo "🚀 Docker installation script started..."

# Check if Docker is already installed
if command -v docker &>/dev/null; then
    echo "Detected installed Docker: $(docker --version)"
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

# Attempt to install Docker (official source)
echo "⚙️  Attempting to install Docker (official source)..."
sudo apt update
if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
    echo "✅ Docker installed successfully! (Official source)"
    docker --version
else
    echo "❌ Official source installation failed! Trying alternative sources..."

    # Select alternative mirror source
    echo "Choose an alternative mirror source:"
    echo "1) Aliyun (Alibaba Cloud)"
    echo "2) Tsinghua University Mirror"
    read -p "Enter your choice (1/2): " source_choice

    if [ "$source_choice" == "1" ]; then
        echo "🔄 Switching to Aliyun source..."
        curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository \
            "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
    elif [ "$source_choice" == "2" ]; then
        echo "🔄 Switching to Tsinghua Mirror..."
        curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository \
            "deb [arch=amd64] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
    else
        echo "❌ Invalid option, exiting script."
        exit 1
    fi

    # Update package index again
    echo "🔄 Updating package index..."
    sudo apt update

    # Attempt to install Docker again
    echo "⚙️  Attempting to install Docker (alternative source)..."
    if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
        echo "✅ Docker installed successfully! (Alternative source)"
        docker --version
    else
        echo "❌ Docker installation failed, please check the error logs."
        exit 1
    fi
fi

configure_docker_proxy() {
    echo "🌍 Enter Docker mirror accelerator addresses (separate multiple addresses with spaces, e.g., https://registry.docker-cn.com https://mirror.ccs.tencentyun.com), or press Enter to skip:"
    read -r proxy_urls
    if [[ -z "$proxy_urls" ]]; then
        echo "⏭ Skipping proxy configuration."
        return 0
    fi

    # Check for jq tool
    if ! command -v jq &>/dev/null; then
        echo "🛠 Installing jq tool..."
        if ! (sudo apt install -y jq 2>/dev/null || sudo yum install -y jq 2>/dev/null || sudo dnf install -y jq 2>/dev/null || sudo pacman -S --noconfirm jq 2>/dev/null || sudo zypper install -y jq 2>/dev/null); then
            echo "❌ Unable to install jq automatically, please install it manually and retry."
            return 1
        fi
    fi

    # Ensure /etc/docker directory exists
    sudo mkdir -p /etc/docker

    # Configuration file handling
    config_file="/etc/docker/daemon.json"
    tmp_file=$(mktemp)

    # Convert input URLs into JSON array format
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

    # Ensure the target file exists
    sudo touch "$config_file"

    # Apply configuration
    sudo mv "$tmp_file" "$config_file"
    sudo chmod 600 "$config_file"

    echo "🔄 Restarting Docker service..."
    sudo systemctl restart docker

    # Verify configuration
    echo "✅ Verifying configuration..."
    if sudo docker info 2>/dev/null | grep -q "$(echo "$proxy_urls" | awk '{print $1}')"; then
        echo "✅ Proxy configuration successful!"
    else
        echo "❌ Proxy configuration may not have taken effect, please check the following:"
        echo "1. Ensure the entered mirror addresses are correct."
        echo "2. Run 'sudo docker info' to check Registry Mirrors."
        echo "3. Check the file permissions and content of /etc/docker/daemon.json."
    fi
}

# Ask user whether to configure Docker mirror accelerator
read -p "Do you want to configure a Docker mirror accelerator? (y/N): " configure_proxy
if [[ "$configure_proxy" =~ ^[Yy]$ ]]; then
    configure_docker_proxy
else
    echo "⏭ Skipping mirror accelerator configuration."
fi

# Ask user whether to enable Docker auto-start at boot
read -p "Do you want to enable Docker auto-start at boot? (y/N): " autostart_choice
if [[ "$autostart_choice" =~ ^[Yy]$ ]]; then
    echo "🚀 Enabling Docker auto-start at boot..."
    if sudo systemctl enable docker; then
        echo "✅ Docker is now set to start automatically at boot!"
    else
        echo "❌ Failed to enable Docker auto-start, please check the error logs."
    fi
else
    echo "⏭ Skipping Docker auto-start configuration."
fi

echo "🎉 Docker installation and configuration completed!"
exit 0
