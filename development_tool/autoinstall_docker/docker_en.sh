#!/bin/bash

# Check if executed as root or with sudo privileges
if [ "$(id -u)" != "0" ]; then
    echo "Please run this script as root or using sudo."
    exit 1
fi

echo "🚀 Starting Docker installation script..."

# Check if Docker is already installed
if command -v docker &>/dev/null; then
    echo "Detected Docker installation: $(docker --version)"
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
        echo "⏭ Skipping uninstall step."
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

# Attempt to install Docker (official repository)
echo "⚙️  Attempting to install Docker (official repository)..."
sudo apt update
if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
    echo "✅ Docker installed successfully! (official repository)"
    docker --version
else
    echo "❌ Official repository installation failed! Trying to switch to domestic repository..."

    # Choose domestic mirror
    echo "Choose domestic mirror:"
    echo "1) Aliyun Mirror"
    echo "2) Tsinghua Mirror"
    read -p "Enter option (1/2): " source_choice

    if [ "$source_choice" == "1" ]; then
        echo "🔄 Switching to Aliyun mirror..."
        curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository \
            "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
    elif [ "$source_choice" == "2" ]; then
        echo "🔄 Switching to Tsinghua mirror..."
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
    echo "⚙️  Attempting to install Docker (domestic repository)..."
    if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
        echo "✅ Docker installed successfully! (domestic repository)"
        docker --version
    else
        echo "❌ Docker installation failed, please check the error logs."
        exit 1
    fi
fi

# Configure Docker image accelerator
configure_docker_proxy() {
    echo "🌍 Please enter the Docker image accelerator URL (e.g., https://registry.docker-cn.com), press Enter to skip:"
    read proxy_url
    if [[ -z "$proxy_url" ]]; then
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

    # Handle configuration file
    config_file="/etc/docker/daemon.json"
    tmp_file=$(mktemp)

    if [ -f "$config_file" ]; then
        jq --arg url "$proxy_url" '."registry-mirrors" = [$url]' "$config_file" > "$tmp_file"
    else
        echo "{\"registry-mirrors\": [\"$proxy_url\"]}" | jq . > "$tmp_file"
    fi

    # Ensure target file exists
    sudo touch "$config_file"

    # Apply configuration
    sudo mv "$tmp_file" "$config_file"
    sudo chmod 600 "$config_file"

    echo "🔄 Restarting Docker service..."
    sudo systemctl restart docker

    # Self-check configuration
    echo "✅ Verifying configuration..."
    if sudo docker info 2>/dev/null | grep -q "$proxy_url"; then
        echo "✅ Proxy configuration verified successfully!"
    else
        echo "❌ Proxy configuration may not have taken effect, please check the following:"
        echo "1. Ensure the entered mirror URL is correct."
        echo "2. Manually run 'sudo docker info' to check Registry Mirrors."
        echo "3. Check the permissions and content of /etc/docker/daemon.json."
    fi
}

# Ask user whether to configure image accelerator
read -p "Do you want to configure Docker image accelerator? (y/N): " configure_proxy
if [[ "$configure_proxy" =~ ^[Yy]$ ]]; then
    configure_docker_proxy
else
    echo "⏭ Skipping image accelerator configuration."
fi

echo "🎉 Docker installation and configuration complete!"
exit 0
