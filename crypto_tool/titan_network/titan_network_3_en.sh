#!/bin/bash

# Titan Docker Deployment Script
LOG_FILE="$HOME/titan_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Log message function
log_message() {
    echo "$1"
}

# Error handling function with user options
handle_error() {
    log_message "Error occurred: $1"
    log_message "1) Retry\n2) Skip\n3) Exit"
    read -p "Enter your choice (1/2/3): " choice
    case "$choice" in
        1) return 1 ;; # Retry
        2) return 0 ;; # Skip
        3) exit 1 ;; # Exit script
        *) log_message "Invalid input, exiting script."
           exit 1 ;;
    esac
}

# Check and install Docker
install_docker() {
    if ! command -v docker &>/dev/null; then
        log_message "Docker is not installed, installing Docker..."
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case "$ID" in
                ubuntu|debian)
                    sudo apt-get update && sudo apt-get install -y \
                        apt-transport-https ca-certificates curl software-properties-common || return 1

                    curl -fsSL https://download.docker.com/linux/$ID/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || return 1

                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$ID $(lsb_release -cs) stable" | \
                        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || return 1

                    sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io || return 1
                    ;;
                centos|rhel)
                    sudo yum install -y yum-utils || return 1
                    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || return 1
                    sudo yum install -y docker-ce docker-ce-cli containerd.io || return 1
                    ;;
                *)
                    log_message "Unsupported operating system."
                    return 1
                    ;;
            esac
            sudo systemctl start docker || return 1
            sudo systemctl enable docker || return 1
        else
            log_message "Could not determine operating system type."
            return 1
        fi
        log_message "Docker installation completed."
    else
        log_message "Docker is already installed, skipping installation."
    fi
}

# Clean old node data
clean_old_data() {
    if [ -d "$HOME/.titanedge" ]; then
        log_message "Old node data detected. Do you want to clean it? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf "$HOME/.titanedge" || return 1
            log_message "Old node data has been cleaned."
        else
            log_message "Skipping old node data cleanup."
        fi
    else
        log_message "No old node data found, skipping cleanup."
    fi
}

# Check Titan node status
check_titan_status() {
    if docker ps --filter "ancestor=nezha123/titan-edge" --format "{{.ID}}" | grep -q .; then
        log_message "Titan node is already running, skipping deployment."
        return 0
    fi
    return 1
}

# Download Titan image and deploy node
deploy_titan_node() {
    check_titan_status && return
    mkdir -p "$HOME/.titanedge" || return 1
    log_message "Downloading Titan Docker image..."
    if ! docker pull nezha123/titan-edge; then
        return 1
    fi
    log_message "Starting Titan node..."
    if ! docker run --network=host -d -v "$HOME/.titanedge:/root/.titanedge" nezha123/titan-edge; then
        return 1
    fi
}

# Bind identity code
bind_identity() {
    log_message "Please enter your binding identity code:"
    read -p "Identity code: " IDENTITY_CODE
    log_message "Binding identity code..."
    if ! docker run --rm -it \
         -v "$HOME/.titanedge:/root/.titanedge" \
         nezha123/titan-edge \
         bind --hash="$IDENTITY_CODE" https://api-test1.container1.titannet.io/api/v2/device/binding; then
        return 1
    fi
    log_message "Identity code binding successful."
}

# Upgrade Titan node
upgrade_titan_node() {
    log_message "A new version of Titan node is available. Do you want to upgrade? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log_message "Upgrading Titan node..."
        # Stop and remove old container
        docker stop $(docker ps --filter "ancestor=nezha123/titan-edge" --format "{{.ID}}") || return 1
        docker rm $(docker ps --filter "ancestor=nezha123/titan-edge" --format "{{.ID}}") || return 1
        # Pull new image and restart
        if ! docker pull nezha123/titan-edge; then
            return 1
        fi
        if ! docker run --network=host -d -v "$HOME/.titanedge:/root/.titanedge" nezha123/titan-edge; then
            return 1
        fi
        log_message "Titan node upgrade completed."
    else
        log_message "Skipping Titan node upgrade."
    fi
}

# Main function
main() {
    log_message "Starting Titan Docker node deployment..."
    while ! install_docker; do
        handle_error "Docker installation failed."
        [ $? -eq 0 ] && break
    done
    while ! clean_old_data; do
        handle_error "Failed to clean old data."
        [ $? -eq 0 ] && break
    done
    while ! deploy_titan_node; do
        handle_error "Titan node deployment failed."
        [ $? -eq 0 ] && break
    done
    while ! bind_identity; do
        handle_error "Identity code binding failed."
        [ $? -eq 0 ] && break
    done
    while ! upgrade_titan_node; do
        handle_error "Titan node upgrade failed."
        [ $? -eq 0 ] && break
    done
    log_message "Titan node successfully deployed or upgraded."
}

# Execute main function
main
