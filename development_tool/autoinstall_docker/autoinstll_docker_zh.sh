#!/bin/bash

# 检查是否以 root 用户或具有 sudo 权限执行
if [ "$(id -u)" != "0" ]; then
    echo "请以 root 用户或使用 sudo 运行该脚本。"
    exit 1
fi

echo "🚀 Docker 安装脚本开始..."

# 检查是否已安装 Docker
if command -v docker &>/dev/null; then
    echo "检测到已安装 Docker：$(docker --version)"
    read -p "是否卸载当前 Docker？(y/N): " remove_docker
    if [[ "$remove_docker" =~ ^[Yy]$ ]]; then
        echo "🛠 正在卸载 Docker..."
        sudo apt remove -y docker-desktop
        rm -r $HOME/.docker/desktop 2>/dev/null || echo "无残余目录需要清理。"
        sudo rm /usr/local/bin/com.docker.cli 2>/dev/null || echo "无残余文件需要清理。"
        sudo apt purge -y docker-desktop docker-ce docker-ce-cli containerd.io
        sudo rm -rf /var/lib/docker /etc/docker
        echo "✅ Docker 已卸载。"
    else
        echo "⏭ 跳过卸载步骤。"
    fi
fi

# 更新软件包索引
echo "🔄 更新软件包索引..."
sudo apt update

# 添加 Docker 官方源
echo "🌍 添加 Docker 官方源..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# 尝试安装 Docker (官方源)
echo "⚙️  尝试安装 Docker (官方源)..."
sudo apt update
if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
    echo "✅ Docker 安装成功！(官方源)"
    docker --version
else
    echo "❌ 官方源安装失败！尝试切换到国内源..."

    # 选择国内镜像源
    echo "选择国内镜像源:"
    echo "1) 阿里源"
    echo "2) 清华源"
    read -p "输入选项 (1/2): " source_choice

    if [ "$source_choice" == "1" ]; then
        echo "🔄 切换到阿里源..."
        curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository \
            "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
    elif [ "$source_choice" == "2" ]; then
        echo "🔄 切换到清华源..."
        curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository \
            "deb [arch=amd64] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
    else
        echo "❌ 无效选项，脚本退出。"
        exit 1
    fi

    # 重新更新软件包索引
    echo "🔄 更新软件包索引..."
    sudo apt update

    # 尝试再次安装 Docker
    echo "⚙️  尝试安装 Docker (国内源)..."
    if sudo apt install -y docker-ce docker-ce-cli containerd.io; then
        echo "✅ Docker 安装成功！(国内源)"
        docker --version
    else
        echo "❌ Docker 安装失败，请检查错误日志。"
        exit 1
    fi
fi

# 配置 Docker 镜像加速器
configure_docker_proxy() {
    echo "🌍 请输入 Docker 镜像加速器地址（例如：https://registry.docker-cn.com），按 Enter 跳过："
    read proxy_url
    if [[ -z "$proxy_url" ]]; then
        echo "⏭ 跳过代理配置。"
        return 0
    fi

    # 检查 jq 工具
    if ! command -v jq &>/dev/null; then
        echo "🛠 正在安装 jq 工具..."
        if ! (sudo apt install -y jq 2>/dev/null || sudo yum install -y jq 2>/dev/null || sudo dnf install -y jq 2>/dev/null || sudo pacman -S --noconfirm jq 2>/dev/null || sudo zypper install -y jq 2>/dev/null); then
            echo "❌ 无法自动安装 jq，请手动安装后重试。"
            return 1
        fi
    fi

    # 处理配置文件
    config_file="/etc/docker/daemon.json"
    tmp_file=$(mktemp)

    if [ -f "$config_file" ]; then
        jq --arg url "$proxy_url" '."registry-mirrors" = [$url]' "$config_file" > "$tmp_file"
    else
        echo "{\"registry-mirrors\": [\"$proxy_url\"]}" | jq . > "$tmp_file"
    fi

    # 应用配置
    sudo mv "$tmp_file" "$config_file"
    sudo chmod 600 "$config_file"

    echo "🔄 重启 Docker 服务..."
    sudo systemctl restart docker

    # 自检配置
    echo "✅ 正在验证配置..."
    if sudo docker info 2>/dev/null | grep -q "$proxy_url"; then
        echo "✅ 代理配置验证成功！"
    else
        echo "❌ 代理配置可能未生效，请检查以下内容："
        echo "1. 确保输入的镜像地址正确"
        echo "2. 手动运行 'sudo docker info' 检查 Registry Mirrors"
        echo "3. 检查文件 /etc/docker/daemon.json 的权限和内容"
    fi
}

# 询问用户是否配置镜像加速器
read -p "是否配置 Docker 镜像加速器？(y/N): " configure_proxy
if [[ "$configure_proxy" =~ ^[Yy]$ ]]; then
    configure_docker_proxy
else
    echo "⏭ 跳过镜像加速器配置。"
fi

echo "🎉 Docker 安装与配置完成！"
exit 0
