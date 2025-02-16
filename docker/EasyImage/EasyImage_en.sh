#!/bin/bash

# Ensure running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root or use sudo."
    exit 1
fi

# Interactive input for port number and installation directory
echo "Enter the port number for EasyImage (default: 8090):"
read -r user_port
EASYIMAGE_PORT=${user_port:-8090}

echo "Enter the installation directory for EasyImage (default: /etc/docker/easyimage):"
read -r user_dir
EASYIMAGE_DIR=${user_dir:-/etc/docker/easyimage}

# Enable auto-start on boot
echo "Enable auto-start on boot? (y/n, default: y)"
read -r enable_autostart
ENABLE_AUTOSTART=${enable_autostart:-y}

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Please install Docker using the following command:"
    echo "bash <(curl -sSL https://raw.githubusercontent.com/Hellohistory/BitAuto/refs/heads/main/docker/install_docker/docker_zh.sh)"
    echo "or"
    echo "bash <(curl -sSL https://gitee.com/hellohistory/BitAuto/raw/main/docker/install_docker/docker_zh.sh)"
    exit 1
fi

# Ensure Docker is running
if ! systemctl is-active --quiet docker; then
    echo "Docker is not running. Starting Docker..."
    systemctl start docker
fi

# Check for Docker Compose (supporting the new `docker compose`)
if command -v docker compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo "Docker Compose is not installed. Installing Docker Compose..."
    apt update && apt install -y docker-compose
    DOCKER_COMPOSE_CMD="docker-compose"
fi

# Check if the port is already in use
if ss -tuln | grep -q ":$EASYIMAGE_PORT"; then
    echo "Warning: Port $EASYIMAGE_PORT is already in use. Please rerun the script and enter a different port number."
    exit 1
fi

# Create and enter the installation directory
mkdir -p "$EASYIMAGE_DIR"
cd "$EASYIMAGE_DIR" || { echo "Failed to enter directory $EASYIMAGE_DIR"; exit 1; }

# Create EasyImage-docker-compose.yaml configuration file
cat > EasyImage-docker-compose.yaml <<EOF
version: '3'
services:
  easyimage:
    image: ddsderek/easyimage:latest
    container_name: easyimage
    ports:
      - '${EASYIMAGE_PORT}:80'  # Customizable port
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

# Display the EasyImage-docker-compose.yaml configuration
echo "EasyImage-docker-compose.yaml configuration file created:"
cat EasyImage-docker-compose.yaml

# Start EasyImage
echo "Starting EasyImage..."
$DOCKER_COMPOSE_CMD -f EasyImage-docker-compose.yaml up -d

# Configure Docker Compose service for auto-start on boot (optional)
if [ "$ENABLE_AUTOSTART" = "y" ]; then
    echo "Creating EasyImage auto-start service..."
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
    echo "EasyImage auto-start configuration completed!"
fi

# Check container status
docker ps | grep easyimage

# Automatically open firewall port
if systemctl is-active --quiet firewalld; then
    firewall-cmd --add-port="${EASYIMAGE_PORT}"/tcp --permanent
    firewall-cmd --reload
    echo "Firewall port opened: ${EASYIMAGE_PORT}"
elif command -v iptables &> /dev/null; then
    iptables -I INPUT -p tcp --dport "${EASYIMAGE_PORT}" -j ACCEPT
    echo "iptables port opened: ${EASYIMAGE_PORT}"
fi

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "EasyImage installation and configuration completed! Access it at: http://${SERVER_IP}:${EASYIMAGE_PORT}"
