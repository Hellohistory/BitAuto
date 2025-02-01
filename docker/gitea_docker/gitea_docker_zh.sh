#!/bin/bash

# 检查 Docker 是否已安装（需要用户手动安装）
function check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker 未安装，请手动安装 Docker 后再运行本脚本。"
        echo "👉 安装指南: https://docs.docker.com/get-docker/"
        exit 1
    else
        echo "✅ Docker 已安装：$(docker --version)"
    fi
}

# 检查 wget 或 curl 是否安装，如果没有则自动安装
function check_and_install_wget_or_curl() {
    if command -v wget &> /dev/null || command -v curl &> /dev/null; then
        echo "✅ wget 或 curl 已安装。"
        return
    fi

    echo "❌ 未找到 wget 或 curl，正在尝试安装..."

    # 检测包管理器
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y wget curl
    elif command -v yum &> /dev/null; then
        sudo yum install -y wget curl
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y wget curl
    else
        echo "❌ 无法自动安装 wget 或 curl，请手动安装后再运行本脚本。"
        exit 1
    fi

    if command -v wget &> /dev/null || command -v curl &> /dev/null; then
        echo "✅ wget 和 curl 安装成功。"
    else
        echo "❌ wget 和 curl 安装失败，请手动安装后再运行本脚本。"
        exit 1
    fi
}

# 让用户输入 MySQL 连接信息
function configure_mysql_connection() {
    echo "🔧 请提供本地 MySQL 服务器的信息："
    read -r -p "👉 请输入 MySQL 服务器地址（默认：127.0.0.1）: " mysql_host
    mysql_host=${mysql_host:-127.0.0.1}

    read -r -p "👉 请输入 MySQL 端口号（默认：3306）: " mysql_port
    mysql_port=${mysql_port:-3306}

    read -r -p "👉 请输入 MySQL 用户名（默认：gitea）: " mysql_user
    mysql_user=${mysql_user:-gitea}

    read -r -p "👉 请输入 MySQL 密码（默认：gitea）: " mysql_password
    mysql_password=${mysql_password:-gitea}

    read -r -p "👉 请输入 MySQL 数据库名称（默认：gitea）: " mysql_db
    mysql_db=${mysql_db:-gitea}

    # 测试 MySQL 连接
    echo "🔄 正在测试 MySQL 连接..."
    if ! mysql -h "$mysql_host" -P "$mysql_port" -u "$mysql_user" -p"$mysql_password" -e "USE $mysql_db;" &>/dev/null; then
        echo "❌ 无法连接到 MySQL，请检查您的输入是否正确！"
        exit 1
    else
        echo "✅ MySQL 连接成功！"
    fi
}

# 生成 Docker Compose 配置
function configure_docker_compose() {
    echo "🚀 生成 gitea-docker-compose.yml..."

    read -r -p "📌 请输入 Gitea 服务的名称（默认：gitea）: " service_name
    service_name=${service_name:-gitea}

    read -r -p "🔑 请输入 Gitea SSH 端口（默认：20022）: " ssh_port
    ssh_port=${ssh_port:-20022}

    read -r -p "🌐 请输入 Gitea HTTP 端口（默认：30000）: " http_port
    http_port=${http_port:-30000}

    read -r -p "📛 请输入应用程序标题（默认：Gitea）: " app_name
    app_name=${app_name:-"Gitea"}

    # 备份现有文件
    if [ -f gitea-docker-compose.yml ]; then
        mv gitea-docker-compose.yml gitea-docker-compose.yml.bak
        echo "⚠️ 现有 gitea-docker-compose.yml 文件已备份为 gitea-docker-compose.yml.bak"
    fi

    # 生成 gitea-docker-compose.yml
    cat <<EOF > gitea-docker-compose.yml
version: "3"

networks:
  gitea:
    external: false

services:
  gitea:
    image: gitea/gitea:latest
    container_name: $service_name
    environment:
      - GITEA__database__DB_TYPE=mysql
      - GITEA__database__HOST=$mysql_host:$mysql_port
      - GITEA__database__NAME=$mysql_db
      - GITEA__database__USER=$mysql_user
      - GITEA__database__PASSWD=$mysql_password
      - SSH_PORT=$ssh_port
      - APP_NAME="$app_name"
    restart: always
    networks:
      - gitea
    ports:
      - "$http_port:3000"
      - "$ssh_port:22"
    volumes:
      - ./gitea:/data
EOF

    echo "✅ gitea-docker-compose.yml 生成完成！"

    # 启动 Gitea
    echo "🚀 启动 Gitea..."
    docker-compose up -d
    echo "✅ Gitea 启动成功！请访问 http://localhost:$http_port"
}

function main() {
    check_docker_installed
    check_and_install_wget_or_curl
    configure_mysql_connection
    configure_docker_compose
}

main
