#!/bin/bash

set -e

function check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker 未安装，请手动安装 Docker 后再运行本脚本。"
        exit 1
    else
        echo "✅ Docker 已安装：$(docker --version)"
    fi
}

function check_and_install_wget_or_curl() {
    if command -v wget &> /dev/null || command -v curl &> /dev/null; then
        echo "✅ wget 或 curl 已安装。"
        return
    fi
    echo "❌ 未找到 wget 或 curl，正在尝试安装..."
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y wget curl
    elif command -v yum &> /dev/null; then
        sudo yum install -y wget curl
    else
        echo "❌ 无法自动安装 wget 或 curl，请手动安装后再运行本脚本。"
        exit 1
    fi
}

function configure_docker_compose_sqlite() {
    echo "🚀 准备生成 gitea-docker-compose.yml..."

    read -r -p "📌 请输入 Gitea 服务容器名称（默认：gitea）: " service_name
    service_name=${service_name:-gitea}

    read -r -p "🔑 请输入 Gitea SSH 端口（默认：2222）: " ssh_port
    ssh_port=${ssh_port:-2222}

    read -r -p "🌐 请输入 Gitea HTTP 端口（默认：3000）: " http_port
    http_port=${http_port:-3000}

    read -r -p "📛 请输入应用标题（默认：Gitea）: " app_name
    app_name=${app_name:-"Gitea"}

    if [ -f gitea-docker-compose.yml ]; then
        mv gitea-docker-compose.yml gitea-docker-compose.yml.bak
        echo "⚠️ 备份旧的 docker-compose 文件为 gitea-docker-compose.yml.bak"
    fi

    cat <<EOF > gitea-docker-compose.yml
version: "3"

networks:
  gitea:
    driver: bridge

volumes:
  gitea-data:

services:
  server:
    image: gitea/gitea:1.23.8
    container_name: $service_name
    restart: always
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=sqlite3
      - GITEA__web__APP_NAME=$app_name
      - GITEA__web__ROOT_URL=http://localhost:$http_port/
    networks:
      - gitea
    volumes:
      - gitea-data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "$http_port:3000"
      - "$ssh_port:22"
EOF

    echo "✅ 配置文件已生成 ✅"
    echo "🚀 正在启动 Gitea..."

    if docker compose version &>/dev/null; then
        docker compose -f gitea-docker-compose.yml up -d
    elif docker-compose version &>/dev/null; then
        docker-compose -f gitea-docker-compose.yml up -d
    else
        echo "❌ 未检测到 docker compose 命令，请确认已安装 docker-compose-plugin 或 legacy docker-compose"
        exit 1
    fi

    echo "🎉 Gitea 启动成功！访问地址：http://localhost:$http_port"
}

function setup_systemd_autostart() {
    echo "🛠️ 配置开机自启服务..."

    current_path=$(pwd)

    cat <<EOF | sudo tee /etc/systemd/system/gitea-docker.service >/dev/null
[Unit]
Description=Gitea (via Docker Compose, SQLite)
Requires=docker.service
After=docker.service

[Service]
WorkingDirectory=$current_path
ExecStart=/usr/bin/docker compose -f gitea-docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f gitea-docker-compose.yml down
Restart=always
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reexec
    sudo systemctl daemon-reload
    sudo systemctl enable gitea-docker
    sudo systemctl restart gitea-docker

    echo "✅ Gitea 已注册为 systemd 服务并设置开机自启。"
}

function main() {
    check_docker_installed
    check_and_install_wget_or_curl
    configure_docker_compose_sqlite
    setup_systemd_autostart
}

main
