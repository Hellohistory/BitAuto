#!/bin/bash
set -e

echo "📦 阿里云 ECS 专用：开始安装 Docker（支持 Ubuntu 24.04）"

# 系统检查
source /etc/os-release
[[ "$ID" != "ubuntu" || "$VERSION_CODENAME" != "noble" ]] && {
  echo "⚠️ 仅支持 Ubuntu 24.04（noble），当前：$ID $VERSION_CODENAME"
  exit 1
}

echo "🧹 清理旧版本"
apt-get remove -y docker docker-engine docker.io containerd runc docker-ce* || true
apt-get update

echo "🧩 安装依赖"
apt-get install -y ca-certificates curl gnupg lsb-release

echo "🔐 导入阿里云 Docker GPG 密钥"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | gpg --dearmor \
  -o /etc/apt/keyrings/docker.gpg

echo "🗂️ 配置 Docker 仓库源"
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "📦 更新并安装 Docker"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "🚀 启动 Docker"
systemctl enable docker
systemctl start docker

echo "✅ Docker 已安装："
docker version

# 镜像加速配置
read -p "是否配置 Docker 镜像加速器? (y/n): " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
  read -p "请输入镜像加速地址（如 https://docker.mirrors.ustc.edu.cn）: " mirror
  if [[ -n "$mirror" ]]; then
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["$mirror"]
}
EOF
    systemctl daemon-reexec
    systemctl restart docker
    echo "✨ 镜像加速已配置"
  fi
fi

echo "🎉 测试 Docker 容器是否可运行..."
docker run --rm hello-world
if [[ $? -eq 0 ]]; then
  echo -e "\n🎊 安装成功！Docker 已完全可用。"
else
  echo -e "\n❌ 安装测试失败，请检查日志并重试。"
fi
