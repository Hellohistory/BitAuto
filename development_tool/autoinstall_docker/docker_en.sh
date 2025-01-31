#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "Please run this script as root or use sudo."
    exit 1
fi

echo "Starting Docker installation script..."

# Detect OS information
OS_NAME=$(grep '^ID=' /etc/os-release | awk -F '=' '{print $2}' | tr -d '"')
OS_VERSION=$(grep '^VERSION_ID=' /etc/os-release | awk -F '=' '{print $2}' | tr -d '"')

# Function to uninstall existing Docker
uninstall_docker() {
    echo "Removing any existing Docker installation..."
    sudo apt remove -y docker-desktop docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>/dev/null || true
    sudo yum remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>/dev/null || true
    sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>/dev/null || true
    sudo pacman -Rns --noconfirm docker docker-compose 2>/dev/null || true
    sudo zypper remove -y docker docker-compose 2>/dev/null || true
}

# Function to add Docker's official GPG key (for Debian/Ubuntu)
add_docker_gpg() {
    echo "Adding Docker's official GPG key..."
    curl -fsSL https://download.docker.com/linux/$OS_NAME/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
}

# Function to configure the official Docker repository (for Debian/Ubuntu)
set_official_mirror() {
    echo "Trying to use the official Docker repository..."
    sudo add-apt-repository \
        "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS_NAME $(lsb_release -cs) stable"
}

# Function to configure Aliyun's mirror (for Debian/Ubuntu)
set_aliyun_mirror() {
    echo "Trying to use Aliyun mirror..."
    curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/$OS_NAME/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    sudo add-apt-repository \
        "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] http://mirrors.aliyun.com/docker-ce/linux/$OS_NAME $(lsb_release -cs) stable"
}

# Function to configure Tsinghua's mirror (for Debian/Ubuntu)
set_tsinghua_mirror() {
    echo "Trying to use Tsinghua mirror..."
    curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/$OS_NAME/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    sudo add-apt-repository \
        "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/$OS_NAME $(lsb_release -cs) stable"
}

# Function to install Docker
install_docker() {
    echo "Attempting to install Docker..."
    case "$OS_NAME" in
        ubuntu | debian)
            sudo apt update
            if sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
                echo "Docker installation successful!"
                docker --version
                exit 0
            fi
            ;;
        centos | rocky | rhel)
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            if sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
                echo "Docker installation successful!"
                docker --version
                exit 0
            fi
            ;;
        fedora)
            sudo dnf install -y dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            if sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
                echo "Docker installation successful!"
                docker --version
                exit 0
            fi
            ;;
        arch)
            sudo pacman -Syu --noconfirm docker docker-compose
            echo "Docker installation successful!"
            docker --version
            exit 0
            ;;
        opensuse)
            sudo zypper install -y docker docker-compose
            echo "Docker installation successful!"
            docker --version
            exit 0
            ;;
        *)
            echo "Unsupported operating system: $OS_NAME"
            exit 1
            ;;
    esac

    echo "Docker installation failed!"
    return 1
}

# === Main Logic ===
uninstall_docker

# If OS is Debian or Ubuntu, handle repository configuration
if [[ "$OS_NAME" == "ubuntu" || "$OS_NAME" == "debian" ]]; then
    add_docker_gpg

    # Try the official repository first
    set_official_mirror
    sudo apt update
    if install_docker; then
        exit 0
    fi

    # If the official repository fails, try Aliyun
    echo "Official repository installation failed, switching to Aliyun mirror..."
    set_aliyun_mirror
    sudo apt update
    if install_docker; then
        exit 0
    fi

    # If Aliyun fails, try Tsinghua
    echo "Aliyun mirror installation failed, switching to Tsinghua mirror..."
    set_tsinghua_mirror
    sudo apt update
    if install_docker; then
        exit 0
    fi
else
    install_docker
fi

echo "Docker installation failed. Please check your network connection or try a manual installation."
exit 1
