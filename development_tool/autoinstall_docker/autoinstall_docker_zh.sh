#!/bin/bash

# 确保以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo "请以 root 用户或使用 sudo 运行该脚本。"
    exit 1
fi

echo "Docker 安装脚本开始..."

# 获取系统信息
OS_NAME=$(grep '^ID=' /etc/os-release | awk -F '=' '{print $2}' | tr -d '"')
# shellcheck disable=SC2034
OS_VERSION=$(grep '^VERSION_ID=' /etc/os-release | awk -F '=' '{print $2}' | tr -d '"')

# 卸载已有的 Docker
uninstall_docker() {
    echo "正在卸载已有的 Docker..."
    sudo apt remove -y docker-desktop docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>/dev/null || true
    sudo yum remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>/dev/null || true
    sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>/dev/null || true
    sudo pacman -Rns --noconfirm docker docker-compose 2>/dev/null || true
    sudo zypper remove -y docker docker-compose 2>/dev/null || true
}

# 添加 Docker 官方 GPG 密钥（适用于 Debian/Ubuntu）
add_docker_gpg() {
    echo "添加 Docker 官方 GPG 密钥..."
    curl -fsSL https://download.docker.com/linux/$OS_NAME/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
}

# 配置官方源（适用于 Debian/Ubuntu）
set_official_mirror() {
    echo "尝试使用官方源..."
    sudo add-apt-repository \
        "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS_NAME $(lsb_release -cs) stable"
}

# 配置阿里云源（适用于 Debian/Ubuntu）
set_aliyun_mirror() {
    echo "尝试使用阿里云源..."
    curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/$OS_NAME/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    sudo add-apt-repository \
        "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] http://mirrors.aliyun.com/docker-ce/linux/$OS_NAME $(lsb_release -cs) stable"
}

# 配置清华源（适用于 Debian/Ubuntu）
set_tsinghua_mirror() {
    echo "尝试使用清华源..."
    curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/$OS_NAME/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    sudo add-apt-repository \
        "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/$OS_NAME $(lsb_release -cs) stable"
}

# 安装 Docker
install_docker() {
    echo "尝试安装 Docker..."
    case "$OS_NAME" in
        ubuntu | debian)
            sudo apt update
            if sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
                echo "Docker 安装成功！"
                docker --version
                exit 0
            fi
            ;;
        centos | rocky | rhel)
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            if sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
                echo "Docker 安装成功！"
                docker --version
                exit 0
            fi
            ;;
        fedora)
            sudo dnf install -y dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            if sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
                echo "Docker 安装成功！"
                docker --version
                exit 0
            fi
            ;;
        arch)
            sudo pacman -Syu --noconfirm docker docker-compose
            echo "Docker 安装成功！"
            docker --version
            exit 0
            ;;
        opensuse)
            sudo zypper install -y docker docker-compose
            echo "Docker 安装成功！"
            docker --version
            exit 0
            ;;
        *)
            echo "不支持的操作系统: $OS_NAME"
            exit 1
            ;;
    esac

    echo "Docker 安装失败！"
    return 1
}

# === 主逻辑 ===
uninstall_docker

# 适用于 Debian/Ubuntu 的 GPG 设置
if [[ "$OS_NAME" == "ubuntu" || "$OS_NAME" == "debian" ]]; then
    add_docker_gpg

    # 先尝试官方源
    set_official_mirror
    sudo apt update
    if install_docker; then
        exit 0
    fi

    # 官方源失败，尝试阿里云源
    echo "官方源安装失败，切换到阿里云源..."
    set_aliyun_mirror
    sudo apt update
    if install_docker; then
        exit 0
    fi

    # 阿里云源失败，尝试清华源
    echo "阿里云源安装失败，切换到清华源..."
    set_tsinghua_mirror
    sudo apt update
    if install_docker; then
        exit 0
    fi
else
    install_docker
fi

echo "Docker 安装失败，请检查网络连接或手动尝试其他安装方式。"
exit 1
