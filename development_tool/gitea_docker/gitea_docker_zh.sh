#!/bin/bash

function check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        echo "Docker 未安装，请先安装 Docker。"
        exit 1
    else
        echo "Docker 已安装：$(docker --version)"
    fi
}

function check_port_in_use() {
    local port=$1
    if lsof -i:$port &> /dev/null || ss -tuln | grep -q ":$port"; then
        echo "端口 $port 已被占用，请选择一个未被占用的端口。"
        return 1
    fi
    return 0
}

function validate_and_check_port() {
    local port=$1
    if [[ ! $port =~ ^[0-9]+$ ]] || [ $port -lt 1024 ] || [ $port -gt 65535 ]; then
        echo "端口号无效，请输入一个有效的端口号（1024-65535）。"
        return 1
    fi
    if ! check_port_in_use $port; then
        return 1
    fi
    return 0
}

function pull_latest_images() {
    echo "正在检查并拉取最新 Docker 镜像..."
    docker pull gitea/gitea:latest
    docker pull mysql:latest
    echo "Docker 镜像已更新。"
}

function configure_docker_compose() {
    echo "是否使用自定义的 gitea-docker-compose.yml 配置文件？（y/n）"
    read use_custom
    if [[ "$use_custom" =~ ^[Yy]$ ]]; then
        echo "请输入自定义配置文件路径："
        read custom_file
        if [ -f "$custom_file" ]; then
            cp "$custom_file" gitea-docker-compose.yml
            echo "已使用自定义的配置文件：$custom_file"
        else
            echo "文件不存在，请检查路径。"
            exit 1
        fi
    else
        # 拉取最新 Docker 镜像
        pull_latest_images

        echo "请输入 Gitea 服务的名称（默认：gitea）:"
        read service_name
        service_name=${service_name:-gitea}

        echo "请输入 Gitea 服务 SSH 端口（默认：20022）:"
        read ssh_port
        ssh_port=${ssh_port:-20022}

        while ! validate_and_check_port $ssh_port; do
            echo "请输入有效且未被占用的 SSH 端口："
            read ssh_port
        done

        echo "请输入 Gitea 服务 HTTP 端口（默认：30000）:"
        read http_port
        http_port=${http_port:-30000}

        while ! validate_and_check_port $http_port; do
            echo "请输入有效且未被占用的 HTTP 端口："
            read http_port
        done

        echo "请输入数据库的密码（默认：gitea）:"
        read db_password
        db_password=${db_password:-gitea}

        echo "请输入应用程序标题（默认：Gitea）:"
        read app_name
        app_name=${app_name:-"Gitea"}

        # 检查 gitea-docker-compose.yml 是否已存在
        if [ -f gitea-docker-compose.yml ]; then
            echo "gitea-docker-compose.yml 文件已存在，是否覆盖？（y/n）"
            read overwrite
            if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
                echo "取消操作，未覆盖文件。"
                exit 0
            fi
        fi

        # 生成 gitea-docker-compose.yml 文件
        cat <<EOF > gitea-docker-compose.yml
version: "3"

networks:
  gitea:
    external: false

services:
  server:
    image: gitea/gitea:latest
    container_name: $service_name
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=mysql
      - GITEA__database__HOST=db:3306
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=gitea
      - GITEA__database__PASSWD=$db_password
      - SSH_PORT=$ssh_port
      - SSH_LISTEN_PORT=22
      - APP_NAME="$app_name"
      - GITEA__log__MODE=file
      - GITEA__log__ROOT_PATH=/data/gitea/log
      - GITEA__log__LEVEL=Debug
      - GITEA__log__FILE_NAME=gitea.log
      - GITEA__log__MAX_DAYS=7
      - GITEA__log__MAX_SIZE_SHIFT=23
    restart: always
    networks:
      - gitea
    volumes:
      - ./gitea:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "$http_port:3000"
      - "$ssh_port:22"
    depends_on:
      - db
  db:
    image: mysql:latest
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=$db_password
      - MYSQL_USER=gitea
      - MYSQL_PASSWORD=$db_password
      - MYSQL_DATABASE=gitea
    networks:
      - gitea
    command:
      - --default-authentication-plugin=mysql_native_password
      - --character-set-server=utf8
      - --collation-server=utf8_bin
    volumes:
      - ./mysql:/var/lib/mysql
EOF

        echo "gitea-docker-compose.yml 已生成。"
    fi
}

check_docker_installed
configure_docker_compose
