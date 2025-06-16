#!/bin/bash
set -e

echo "📦 开始安装 Docker，并自动使用清华镜像源加速..."

# 检测系统
source /etc/os-release
ID=${ID,,}
VERSION_CODENAME=${VERSION_CODENAME:-$(. /etc/os-release && echo "$VERSION_CODENAME")}

echo "🔍 当前系统: $ID $VERSION"

# 清理旧版本
echo "🧹 清理旧版本 Docker..."
remove_old_packages=(
    docker docker-client docker-client-latest docker-common
    docker-latest docker-latest-logrotate docker-logrotate
    docker-engine docker.io docker-doc docker-compose podman-docker containerd runc
)
for pkg in "${remove_old_packages[@]}"; do
    if command -v apt-get &>/dev/null; then
        apt-get -y remove $pkg || true
    elif command -v yum &>/dev/null || command -v dnf &>/dev/null; then
        (yum -y remove $pkg || dnf -y remove $pkg) || true
    fi
done

# 按不同系统安装
if [[ "$ID" == "debian" || "$ID" == "ubuntu" || "$ID" == "raspbian" ]]; then
    echo "🧩 安装依赖..."
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release

    echo "🔐 添加 Docker GPG 密钥..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "🗂️ 添加 Docker 清华源..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/$ID \
      $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    echo "📦 安装 Docker..."
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

elif [[ "$ID" == "centos" || "$ID" == "rhel" ]]; then
    echo "🧩 安装 yum-utils..."
    yum install -y yum-utils

    echo "🗂️ 添加 Docker 源并替换为清华镜像..."
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sed -i 's+https://download.docker.com+https://mirrors.tuna.tsinghua.edu.cn/docker-ce+' /etc/yum.repos.d/docker-ce.repo

    echo "📦 安装 Docker..."
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

elif [[ "$ID" == "fedora" ]]; then
    echo "🧩 安装 dnf-plugins-core..."
    dnf -y install dnf-plugins-core

    echo "🗂️ 添加 Docker 源并替换为清华镜像..."
    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    sed -i 's+https://download.docker.com+https://mirrors.tuna.tsinghua.edu.cn/docker-ce+' /etc/yum.repos.d/docker-ce.repo

    echo "📦 安装 Docker..."
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
    echo "❌ 不支持的系统: $ID"
    exit 1
fi

# 配置镜像加速器
echo ""
read -p "⚡ 是否配置 Docker 镜像加速器? (y/n): " config_mirror
if [[ "$config_mirror" == "y" || "$config_mirror" == "Y" ]]; then
    echo "🌐 常用加速器示例（可手动输入）:"
    echo "  阿里云:      https://<你的ID>.mirror.aliyuncs.com"
    echo "  中科大:      https://docker.mirrors.ustc.edu.cn"
    echo "  网易云:      https://hub-mirror.c.163.com"
    echo ""
    read -p "请输入加速器地址（不输入则跳过）: " mirror_url

    if [[ -n "$mirror_url" ]]; then
        echo "📝 写入镜像加速配置到 /etc/docker/daemon.json"
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["$mirror_url"]
}
EOF
    fi
fi

echo "🚀 启动并设置 Docker 开机自启..."
systemctl enable docker
systemctl daemon-reexec
systemctl restart docker

echo "✅ Docker 安装完成！版本如下："
docker version
