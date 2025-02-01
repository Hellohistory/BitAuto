#!/bin/bash

function check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        echo "Docker is not installed. Please install Docker first."
        exit 1
    else
        echo "Docker is installed: $(docker --version)"
    fi
}

function check_port_in_use() {
    local port=$1
    if lsof -i:$port &> /dev/null || ss -tuln | grep -q ":$port"; then
        echo "Port $port is already in use. Please choose an available port."
        return 1
    fi
    return 0
}

function validate_and_check_port() {
    local port=$1
    if [[ ! $port =~ ^[0-9]+$ ]] || [ $port -lt 1024 ] || [ $port -gt 65535 ]; then
        echo "Invalid port number. Please enter a valid port number between 1024 and 65535."
        return 1
    fi
    if ! check_port_in_use $port; then
        return 1
    fi
    return 0
}

function pull_latest_images() {
    echo "Checking and pulling the latest Docker images..."
    docker pull gitea/gitea:latest
    docker pull mysql:latest
    echo "Docker images have been updated."
}

function configure_docker_compose() {
    echo "Do you want to use a custom gitea-docker-compose.yml configuration file? (y/n)"
    read use_custom
    if [[ "$use_custom" =~ ^[Yy]$ ]]; then
        echo "Please enter the path to the custom configuration file:"
        read custom_file
        if [ -f "$custom_file" ]; then
            cp "$custom_file" gitea-docker-compose.yml
            echo "Using the custom configuration file: $custom_file"
        else
            echo "File not found. Please check the path."
            exit 1
        fi
    else
        # Pull the latest Docker images
        pull_latest_images

        echo "Please enter the name of the Gitea service (default: gitea):"
        read service_name
        service_name=${service_name:-gitea}

        echo "Please enter the SSH port for the Gitea service (default: 20022):"
        read ssh_port
        ssh_port=${ssh_port:-20022}

        while ! validate_and_check_port $ssh_port; do
            echo "Please enter a valid and available SSH port:"
            read ssh_port
        done

        echo "Please enter the HTTP port for the Gitea service (default: 30000):"
        read http_port
        http_port=${http_port:-30000}

        while ! validate_and_check_port $http_port; do
            echo "Please enter a valid and available HTTP port:"
            read http_port
        done

        echo "Please enter the database password (default: gitea):"
        read db_password
        db_password=${db_password:-gitea}

        echo "Please enter the application title (default: Gitea):"
        read app_name
        app_name=${app_name:-"Gitea"}

        # Check if gitea-docker-compose.yml exists
        if [ -f gitea-docker-compose.yml ]; then
            echo "gitea-docker-compose.yml file already exists. Do you want to overwrite it? (y/n)"
            read overwrite
            if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
                echo "Operation cancelled. File not overwritten."
                exit 0
            fi
        fi

        # Generate gitea-docker-compose.yml file
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

        echo "gitea-docker-compose.yml has been generated."
    fi
}

check_docker_installed
configure_docker_compose
