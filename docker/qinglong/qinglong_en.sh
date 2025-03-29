#!/bin/bash
set -euo pipefail

# Global configuration
IMAGE_NAME="whyour/qinglong:latest"
CONTAINER_NAME="qinglong"
CONTAINER_PORT=5700
MAX_RETRY=3

# Read valid user input (y/n)
read_yes_no() {
    local prompt="$1"
    local input
    while true; do
        read -p "$prompt" input
        case "$input" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
            *) echo "Please enter y or n." ;;
        esac
    done
}

# Read Qinglong exposed port (default: 5700)
read_exposed_port() {
    local input_port
    read -p "Enter the exposed port for Qinglong (default: 5700): " input_port
    if [ -z "$input_port" ]; then
        EXPOSED_PORT=5700
    else
        EXPOSED_PORT=$input_port
    fi
}

# Check if Docker is installed
check_docker_installed() {
    if command -v docker &>/dev/null; then
        echo "✅ Docker is installed"
        return 0
    else
        echo "❌ Docker is not installed. Please install Docker first."
        echo "Reference installation guide: https://docs.docker.com/engine/install/"
        return 1
    fi
}

# Check if Docker is running
check_docker_running() {
    if docker info &>/dev/null; then
        echo "✅ Docker is running"
        return 0
    else
        echo "⚠️ Docker is installed but not running"
        return 1
    fi
}

# Start Docker service (supports systemctl and service)
start_docker_service() {
    echo "Attempting to start Docker service..."
    if command -v systemctl &>/dev/null; then
        if sudo systemctl start docker; then
            echo "✅ Docker service started successfully (systemctl)"
            return 0
        fi
    elif command -v service &>/dev/null; then
        if sudo service docker start; then
            echo "✅ Docker service started successfully (service)"
            return 0
        fi
    fi
    echo "❌ Failed to start Docker. Please check manually."
    return 1
}

# Validate proxy address format (simple validation)
validate_proxy() {
    local proxy="$1"
    if [[ "$proxy" =~ ^https?://.+ ]]; then
        return 0
    else
        return 1
    fi
}

# Configure Docker proxy
set_docker_proxy() {
    local proxy
    read -p "Enter Docker HTTP/HTTPS proxy address (e.g., http://your.proxy.address:port): " proxy
    if [ -z "$proxy" ]; then
        echo "Proxy address cannot be empty. Cancelling proxy setup."
        return 1
    fi
    if ! validate_proxy "$proxy"; then
        echo "Invalid proxy address format. Please use the correct format (e.g., http://your.proxy.address:port)."
        return 1
    fi
    echo "Configuring Docker proxy as $proxy ..."
    local proxy_conf="/etc/systemd/system/docker.service.d/http-proxy.conf"
    if [ -f "$proxy_conf" ]; then
        echo "Existing Docker proxy configuration detected."
        if ! read_yes_no "Overwrite the existing proxy configuration? (y/n): "; then
            echo "Keeping existing proxy configuration. Cancelling proxy setup."
            return 1
        fi
    fi
    sudo mkdir -p /etc/systemd/system/docker.service.d
    sudo tee "$proxy_conf" > /dev/null <<EOF
[Service]
Environment="HTTP_PROXY=$proxy" "HTTPS_PROXY=$proxy" "NO_PROXY=localhost,127.0.0.1"
EOF
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    echo "✅ Docker proxy configured and service restarted."
}

# Pull image, start Qinglong container automatically, and output access URL
deploy_qinglong() {
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRY ]; do
        echo "🚀 Pulling Qinglong image (Attempt: $((retry_count+1)))..."
        if docker pull "$IMAGE_NAME"; then
            echo "✅ Qinglong image pulled successfully!"
            # If a container with the same name exists, remove the old one first
            if [ "$(docker ps -a -q -f name="^${CONTAINER_NAME}$")" ]; then
                echo "Detected an existing container named ${CONTAINER_NAME}. Removing the old container..."
                docker rm -f "$CONTAINER_NAME"
            fi
            echo "Starting Qinglong container..."
            docker run -dit --name "$CONTAINER_NAME" -p "${EXPOSED_PORT}:${CONTAINER_PORT}" "$IMAGE_NAME"
            # Get public IP
            PUBLIC_IP=$(curl -s ifconfig.me)
            echo "✅ Qinglong container started successfully!"
            echo "Qinglong panel access URL: http://${PUBLIC_IP}:${EXPOSED_PORT}"
            return 0
        else
            echo "❌ Failed to pull image (Attempt: $((retry_count+1))). This may be due to network issues."
            if read_yes_no "Set up Docker proxy and retry? (y/n): "; then
                if ! set_docker_proxy; then
                    echo "Proxy setup failed or cancelled. Aborting image pull."
                    return 1
                fi
            else
                echo "User chose not to set up proxy. Aborting image pull."
                return 1
            fi
        fi
        retry_count=$((retry_count+1))
    done
    echo "❌ Exceeded maximum retry attempts. Failed to pull image."
    return 1
}

# Main workflow
main() {
    echo "🔍 Checking Docker environment..."
    check_docker_installed || exit 1

    if ! check_docker_running; then
        if read_yes_no "Docker is not running. Start Docker service? (y/n): "; then
            start_docker_service || exit 1
            if ! check_docker_running; then
                echo "❌ Docker service still not running. Please check manually."
                exit 1
            fi
        else
            echo "User cancelled Docker service startup. Exiting script."
            exit 0
        fi
    fi

    read_exposed_port
    deploy_qinglong
}

main