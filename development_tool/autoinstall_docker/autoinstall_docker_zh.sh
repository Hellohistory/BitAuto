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

# 检查 Docker 是否已存在
docker_exists() {
    if command -v docker &>/dev/null; then
        return 0
    else
        return 1
    fi
}

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

# 配置 Docker 镜像源
set_mirror() {
    local mirror_url=$1
    echo "尝试使用镜像源: $mirror_url"
    curl -fsSL "$mirror_url/gpg" | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    sudo add-apt-repository \
        "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] $mirror_url/linux/$OS_NAME $(lsb_release -cs) stable"
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
                return 0
            fi
            ;;
        centos | rocky | rhel)
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            if sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
                echo "Docker 安装成功！"
                docker --version
                return 0
            fi
            ;;
        fedora)
            sudo dnf install -y dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            if sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
                echo "Docker 安装成功！"
                docker --version
                return 0
            fi
            ;;
        arch)
            sudo pacman -Syu --noconfirm docker docker-compose
            echo "Docker 安装成功！"
            docker --version
            return 0
            ;;
        opensuse)
            sudo zypper install -y docker docker-compose
            echo "Docker 安装成功！"
            docker --version
            return 0
            ;;
        *)
            echo "不支持的操作系统: $OS_NAME"
            return 1
            ;;
    esac

    echo "Docker 安装失败！"
    return 1
}

# 配置 Docker 镜像加速器
configure_docker_proxy() {
    echo "请输入 Docker 镜像加速器地址（例如：https://registry.example.com），按 Enter 跳过："
    read proxy_url
    if [[ -z "$proxy_url" ]]; then
        echo "跳过代理配置。"
        return 0
    fi

    # 检查 jq 工具
    if ! command -v jq &>/dev/null; then
        echo "正在安装 jq 工具..."
        if ! (sudo apt install -y jq 2>/dev/null || sudo yum install -y jq 2>/dev/null || sudo dnf install -y jq 2>/dev/null || sudo pacman -S --noconfirm jq 2>/dev/null || sudo zypper install -y jq 2>/dev/null); then
            echo "无法自动安装 jq，请手动安装后重试。"
            return 1
        fi
    fi

    # 处理配置文件
    config_file="/etc/docker/daemon.json"
    tmp_file=$(mktemp)

    if [ -f "$config_file" ]; then
        # 合并现有配置
        jq --arg url "$proxy_url" '."registry-mirrors" = [$url]' "$config_file" > "$tmp_file"
    else
        # 创建新配置
        echo "{\"registry-mirrors\": [\"$proxy_url\"]}" | jq . > "$tmp_file"
    fi

    # 应用配置
    sudo mv "$tmp_file" "$config_file"
    sudo chmod 600 "$config_file"

    echo "重启 Docker 服务..."
    sudo systemctl restart docker

    # 自检配置
    echo "正在验证配置..."
    if sudo docker info 2>/dev/null | grep -q "$proxy_url"; then
        echo "✅ 代理配置验证成功！"
    else
        echo "❌ 代理配置可能未生效，请检查以下内容："
        echo "1. 确保输入的镜像地址正确"
        echo "2. 手动运行 'sudo docker info' 检查 Registry Mirrors"
        echo "3. 检查文件 /etc/docker/daemon.json 的权限和内容"
    fi
}

# === 主逻辑 ===

# 检查现有 Docker 安装
if docker_exists; then
    read -p "检测到系统已安装 Docker，是否卸载并重新安装？(Y/n) " choice
    choice=${choice:-Y}
    case "$choice" in
        Y|y )
            uninstall_docker
            ;;
        N|n )
            read -p "是否要配置 Docker 镜像加速器？(Y/n) " proxy_choice
            proxy_choice=${proxy_choice:-Y}
            case "$proxy_choice" in
                Y|y )
                    configure_docker_proxy
                    exit 0
                    ;;
                * )
                    echo "跳过代理配置。"
                    exit 0
                    ;;
            esac
            ;;
        * )
            echo "无效输入，退出脚本。"
            exit 1
            ;;
    esac
fi

# 添加 Docker GPG 密钥并设置源
add_docker_gpg

# 尝试多个镜像源安装 Docker
set_mirror "https://download.docker.com"
sudo apt update
if ! install_docker; then
    echo "官方源安装失败，切换到阿里云源..."
    set_mirror "http://mirrors.aliyun.com"
    sudo apt update
    if ! install_docker; then
        echo "阿里云源安装失败，切换到清华源..."
        set_mirror "https://mirrors.tuna.tsinghua.edu.cn"
        sudo apt update
        install_docker || exit 1
    fi
fi

# 安装后配置
read -p "是否要配置 Docker 镜像加速器？(Y/n) " post_install_choice
post_install_choice=${post_install_choice:-Y}
case "$post_install_choice" in
    Y|y )
        configure_docker_proxy
        ;;
    * )
        echo "跳过代理配置。"
        ;;
esac

echo "脚本执行完成。"
exit 0
