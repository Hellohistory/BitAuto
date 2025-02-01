#!/bin/bash

# Titan Docker Deployment Script

# Error handling function with user choices
handle_error() {
    echo "An error occurred: $1"
    echo -e "1) Retry\n2) Skip\n3) Exit"
    read -p "Please enter your choice (1/2/3): " choice
    case "$choice" in
        1) return 1 ;; # Return 1 indicates retry
        2) return 0 ;; # Return 0 indicates skip
        3) exit 1 ;; # Exit the script
        *) echo "Invalid input, exiting the script."
           exit 1 ;;
    esac
}

# Check and install Docker (using an external script)
install_docker_external() {
    if ! command -v docker &>/dev/null; then
        echo "Docker is not installed, downloading and installing Docker..."
        if ! bash <(curl -sSL https://raw.githubusercontent.com/Hellohistory/BitAuto/refs/heads/main/development_tool/autoinstall_docker/docker_en.sh); then
            return 1
        fi
        echo "Docker installation completed."
    else
        echo "Docker is already installed, skipping installation."
    fi
}

# Clean up old node data
clean_old_data() {
    if [ -d "$HOME/.titanedge" ]; then
        echo "Old node data detected, would you like to clean it up? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf "$HOME/.titanedge" || return 1
            echo "Old node data cleaned up."
        else
            echo "Skipping old node data cleanup."
        fi
    else
        echo "No old node data detected, skipping cleanup."
    fi
}

# Check Titan node status
check_titan_status() {
    if docker ps --filter "ancestor=nezha123/titan-edge" --format "{{.ID}}" | grep -q .; then
        echo "Titan node is already running, skipping deployment."
        return 0
    fi
    return 1
}

# Download Titan image and run the node
deploy_titan_node() {
    check_titan_status && return
    mkdir -p "$HOME/.titanedge" || return 1
    echo "Downloading Titan Docker image..."
    if ! docker pull nezha123/titan-edge; then
        return 1
    fi
    echo "Running Titan node..."
    if ! docker run --network=host -d -v "$HOME/.titanedge:/root/.titanedge" nezha123/titan-edge; then
        return 1
    fi
}

# Bind identity code
bind_identity() {
    echo "Please enter your binding identity code:"
    read -p "Binding identity code: " IDENTITY_CODE
    echo "Binding identity code..."
    if ! docker run --rm -it \
         -v "$HOME/.titanedge:/root/.titanedge" \
         nezha123/titan-edge \
         bind --hash="$IDENTITY_CODE" https://api-test1.container1.titannet.io/api/v2/device/binding; then
        return 1
    fi
    echo "Identity code binding successful."
}

# Upgrade prompt and choice
upgrade_titan_node() {
    echo "A new version of Titan node is available, would you like to upgrade? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Starting Titan node upgrade..."
        # Stop and remove old containers
        docker stop $(docker ps --filter "ancestor=nezha123/titan-edge" --format "{{.ID}}") || return 1
        docker rm $(docker ps --filter "ancestor=nezha123/titan-edge" --format "{{.ID}}") || return 1
        # Pull new image and run
        if ! docker pull nezha123/titan-edge; then
            return 1
        fi
        if ! docker run --network=host -d -v "$HOME/.titanedge:/root/.titanedge" nezha123/titan-edge; then
            return 1
        fi
        echo "Titan node upgrade completed."
    else
        echo "Skipping Titan node upgrade."
    fi
}

# Main function
main() {
    echo "Starting Titan Docker node deployment..."

    # Install Docker
    while ! install_docker_external; do
        handle_error "Docker installation failed."
        if [ $? -ne 1 ]; then
            break
        fi
    done

    # Confirm Docker is installed
    if ! command -v docker &>/dev/null; then
        echo "Docker installation failed, unable to proceed with deployment."
        exit 1
    fi

    # Clean up old data
    while ! clean_old_data; do
        handle_error "Old data cleanup failed."
        if [ $? -ne 1 ]; then
            break
        fi
    done

    # Deploy Titan node
    while ! deploy_titan_node; do
        handle_error "Titan node deployment failed."
        if [ $? -ne 1 ]; then
            break
        fi
    done

    # Bind identity code
    while ! bind_identity; do
        handle_error "Identity code binding failed."
        if [ $? -ne 1 ]; then
            break
        fi
    done

    # Upgrade Titan node
    while ! upgrade_titan_node; do
        handle_error "Titan node upgrade failed."
        if [ $? -ne 1 ]; then
            break
        fi
    done

    echo "Titan node successfully deployed or upgraded."
}

# Call the main function
main
