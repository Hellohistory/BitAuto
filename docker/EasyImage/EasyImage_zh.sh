#!/bin/bash

# 确保以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 用户执行此脚本，或使用 sudo 运行"
    exit 1
fi

# 交互式获取端口号和安装目录
echo "请输入 EasyImage 运行的端口号 (默认: 8090):"
read -r user_port
EASYIMAGE_PORT=${user_port:-8090}

echo "请输入 EasyImage 的安装目录 (默认: /etc/docker/easyimage):"
read -r user_dir
EASYIMAGE_DIR=${user_dir:-/etc/docker/easyimage}

# 是否启用开机自启
echo "是否启用开机自启？(y/n, 默认: y)"
read -r enable_autostart
ENABLE_AUTOSTART=${enable_autostart:-y}

# 检测 Docker 是否已安装
if ! command -v docker &> /dev/null; then
    echo "Docker 未安装，请使用以下命令安装 Docker："
    echo "bash <(curl -sSL https://raw.githubusercontent.com/Hellohistory/BitAuto/refs/heads/main/docker/install_docker/docker_zh.sh)"
    echo "或者"
    echo "bash <(curl -sSL https://gitee.com/hellohistory/BitAuto/raw/main/docker/install_docker/docker_zh.sh)"
    exit 1
fi

# 确保 Docker 运行正常
if ! systemctl is-active --quiet docker; then
    echo "Docker 未运行，正在启动 Docker..."
    systemctl start docker
fi

# 检测 Docker Compose（支持新版 `docker compose`）
if command -v docker compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo "Docker Compose 未安装，正在安装 Docker Compose..."
    apt update && apt install -y docker-compose
    DOCKER_COMPOSE_CMD="docker-compose"
fi

# 端口检测
if ss -tuln | grep -q ":$EASYIMAGE_PORT"; then
    echo "警告: 端口 $EASYIMAGE_PORT 已被占用，请重新运行脚本并输入新的端口号。"
    exit 1
fi

# 创建并进入数据文件夹
mkdir -p "$EASYIMAGE_DIR"
cd "$EASYIMAGE_DIR" || { echo "无法进入目录 $EASYIMAGE_DIR"; exit 1; }

# 创建 EasyImage-docker-compose.yaml 配置文件
cat > EasyImage-docker-compose.yaml <<EOF
version: '3'
services:
  easyimage:
    image: ddsderek/easyimage:latest
    container_name: easyimage
    ports:
      - '${EASYIMAGE_PORT}:80'  # 端口可自定义
    environment:
      - TZ=Asia/Shanghai
      - PUID=1000
      - PGID=1000
      - DEBUG=false
    volumes:
      - ./config:/app/web/config
      - ./i:/app/web/i
    restart: always
EOF

# 显示 EasyImage-docker-compose.yaml 配置
echo "EasyImage-docker-compose.yaml 配置文件已创建："
cat EasyImage-docker-compose.yaml

# 启动 EasyImage
echo "正在启动 EasyImage..."
$DOCKER_COMPOSE_CMD -f EasyImage-docker-compose.yaml up -d

# 设置 Docker Compose 服务开机自启（用户可选）
if [ "$ENABLE_AUTOSTART" = "y" ]; then
    echo "创建 EasyImage 开机自启服务..."
    cat > /etc/systemd/system/easyimage.service <<EOF
[Unit]
Description=EasyImage Service
After=docker.service
Requires=docker.service

[Service]
Restart=always
ExecStart=/usr/bin/${DOCKER_COMPOSE_CMD} -f $EASYIMAGE_DIR/EasyImage-docker-compose.yaml up -d
ExecStop=/usr/bin/${DOCKER_COMPOSE_CMD} -f $EASYIMAGE_DIR/EasyImage-docker-compose.yaml down
WorkingDirectory=$EASYIMAGE_DIR

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable easyimage.service
    systemctl start easyimage.service
    echo "EasyImage 开机自启配置完成！"
fi

# 检查容器运行状态
docker ps | grep easyimage

# 自动开放防火墙端口
if systemctl is-active --quiet firewalld; then
    firewall-cmd --add-port="${EASYIMAGE_PORT}"/tcp --permanent
    firewall-cmd --reload
    echo "已放行防火墙端口: ${EASYIMAGE_PORT}"
elif command -v iptables &> /dev/null; then
    iptables -I INPUT -p tcp --dport "${EASYIMAGE_PORT}" -j ACCEPT
    echo "已放行 iptables 端口: ${EASYIMAGE_PORT}"
fi

# 获取服务器 IP
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "EasyImage 安装配置完成！ 访问地址: http://${SERVER_IP}:${EASYIMAGE_PORT}"
