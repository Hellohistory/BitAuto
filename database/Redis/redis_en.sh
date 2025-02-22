#!/bin/bash

# Check if the user is root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Please run the script as root or with sudo"
        exit 1
    fi
}

# Error handling function
handle_error() {
    echo "An error occurred: $1"
    exit 1
}

# Safely execute command with sudo
execute_with_sudo() {
    # shellcheck disable=SC2145
    sudo "$@" || handle_error "Command failed: $@"
}

# Detect distribution and set the appropriate package manager
get_package_manager() {
    if [ -f "/etc/debian_version" ]; then
        echo "apt"
    elif [ -f "/etc/redhat-release" ]; then
        echo "yum"
    elif [ -f "/etc/centos-release" ]; then
        echo "yum"
    elif [ -f "/etc/fedora-release" ]; then
        echo "dnf"
    elif [ -f "/etc/arch-release" ]; then
        echo "pacman"
    else
        handle_error "Unsupported Linux distribution"
    fi
}

# Get public IP
get_public_ip() {
    echo "Getting public IP..."
    public_ip=$(curl -s http://checkip.amazonaws.com) || handle_error "Unable to get public IP"
    echo "Public IP: $public_ip"
}

# Get local IP
get_local_ip() {
    echo "Getting local IP..."
    local_ip=$(hostname -I | awk '{print $1}') || handle_error "Unable to get local IP"
    echo "Local IP: $local_ip"
}

# Show menu using dialog
show_menu() {
    clear
    choice=$(dialog --title "Redis Management Tool" --menu "Please choose an action" 15 60 9 \
        1 "Install Redis" \
        2 "Update Redis" \
        3 "Uninstall Redis" \
        4 "Start Redis" \
        5 "Stop Redis" \
        6 "Restart Redis" \
        7 "Modify Redis Config" \
        8 "View Current Redis Config" \
        9 "Exit" 2>&1 > /dev/tty)

    case $choice in
        1) install_redis ;;
        2) update_redis ;;
        3) uninstall_redis ;;
        4) start_redis ;;
        5) stop_redis ;;
        6) restart_redis ;;
        7) modify_redis_config ;;
        8) view_redis_config ;;
        9) exit 0 ;;
        *) dialog --msgbox "Invalid option, please choose again." 6 30; show_menu ;;
    esac
}

# Install Redis
install_redis() {
    PACKAGE_MANAGER=$(get_package_manager)

    if dpkg -l | grep -q redis-server; then
        dialog --msgbox "Redis is already installed, skipping installation." 6 30
    else
        dialog --msgbox "Installing Redis..." 6 30
        if [ "$PACKAGE_MANAGER" == "apt" ]; then
            execute_with_sudo apt-get update
            execute_with_sudo apt-get install -y redis-server
        elif [ "$PACKAGE_MANAGER" == "yum" ] || [ "$PACKAGE_MANAGER" == "dnf" ]; then
            execute_with_sudo yum install -y redis
        elif [ "$PACKAGE_MANAGER" == "pacman" ]; then
            execute_with_sudo pacman -S --noconfirm redis
        else
            handle_error "Redis installation is not supported on this distribution."
        fi
        dialog --msgbox "Redis installation completed!" 6 30
    fi

    # Get and display public and local IP
    get_public_ip
    get_local_ip

    show_menu
}

# Update Redis
update_redis() {
    PACKAGE_MANAGER=$(get_package_manager)

    dialog --msgbox "Updating Redis..." 6 30
    if [ "$PACKAGE_MANAGER" == "apt" ]; then
        execute_with_sudo apt-get update
        execute_with_sudo apt-get upgrade -y redis-server
    elif [ "$PACKAGE_MANAGER" == "yum" ] || [ "$PACKAGE_MANAGER" == "dnf" ]; then
        execute_with_sudo yum update -y redis
    elif [ "$PACKAGE_MANAGER" == "pacman" ]; then
        execute_with_sudo pacman -Syu redis
    else
        handle_error "Redis update is not supported on this distribution."
    fi
    dialog --msgbox "Redis update completed!" 6 30
    show_menu
}

# Start Redis
start_redis() {
    if ! systemctl is-active --quiet redis-server; then
        dialog --msgbox "Starting Redis..." 6 30
        execute_with_sudo systemctl start redis-server
        dialog --msgbox "Redis has started!" 6 30
    else
        dialog --msgbox "Redis is already running." 6 30
    fi
    show_menu
}

# Stop Redis
stop_redis() {
    if systemctl is-active --quiet redis-server; then
        dialog --msgbox "Stopping Redis..." 6 30
        execute_with_sudo systemctl stop redis-server
        dialog --msgbox "Redis has stopped." 6 30
    else
        dialog --msgbox "Redis service is not running." 6 30
    fi
    show_menu
}

# Restart Redis
restart_redis() {
    if systemctl is-active --quiet redis-server; then
        dialog --msgbox "Restarting Redis..." 6 30
        execute_with_sudo systemctl restart redis-server
        dialog --msgbox "Redis has restarted!" 6 30
    else
        dialog --msgbox "Redis service is not running, starting Redis..." 6 30
        execute_with_sudo systemctl start redis-server
        dialog --msgbox "Redis has started." 6 30
    fi
    show_menu
}

# Modify Redis configuration
modify_redis_config() {
    CONFIG_FILE="/etc/redis/redis.conf"
    if [ ! -f "$CONFIG_FILE" ]; then
        dialog --msgbox "Redis config file does not exist, please check if Redis is installed." 6 30
        show_menu
    fi

    config_choice=$(dialog --title "Modify Redis Config" --menu "Choose the configuration option to modify" 15 60 4 \
        1 "Max connections (maxclients)" \
        2 "Max memory usage (maxmemory)" \
        3 "Enable persistence (save)" \
        4 "Return" 2>&1 > /dev/tty)

    case $config_choice in
        1) modify_maxclients ;;
        2) modify_maxmemory ;;
        3) modify_persistence ;;
        4) show_menu ;;
        *) dialog --msgbox "Invalid option, please choose again." 6 30; modify_redis_config ;;
    esac
}

# Modify max connections
modify_maxclients() {
    maxclients=$(dialog --inputbox "Enter new max connections (maxclients):" 8 40 2>&1 > /dev/tty)
    execute_with_sudo sed -i "s/^# maxclients .*/maxclients $maxclients/" /etc/redis/redis.conf
    dialog --msgbox "Max connections set to $maxclients" 6 30
    show_menu
}

# Modify max memory usage
modify_maxmemory() {
    maxmemory=$(dialog --inputbox "Enter new max memory usage (maxmemory), e.g. 2gb:" 8 40 2>&1 > /dev/tty)
    execute_with_sudo sed -i "s/^# maxmemory .*/maxmemory $maxmemory/" /etc/redis/redis.conf
    dialog --msgbox "Max memory usage set to $maxmemory" 6 30
    show_menu
}

# Modify persistence setting
modify_persistence() {
    enable_persistence=$(dialog --yesno "Enable persistence?" 6 30 && echo y || echo n)
    if [[ "$enable_persistence" == "y" ]]; then
        execute_with_sudo sed -i "s/^# save .*/save 900 1/" /etc/redis/redis.conf
        dialog --msgbox "Persistence enabled" 6 30
    else
        execute_with_sudo sed -i "s/^# save .*/# save/" /etc/redis/redis.conf
        dialog --msgbox "Persistence disabled" 6 30
    fi
    show_menu
}

# View current Redis config
view_redis_config() {
    CONFIG_FILE="/etc/redis/redis.conf"
    if [ ! -f "$CONFIG_FILE" ]; then
        dialog --msgbox "Redis config file does not exist, please check if Redis is installed." 6 30
        show_menu
    fi

    dialog --textbox "$CONFIG_FILE" 20 80
    show_menu
}

# Start menu
check_root
show_menu
