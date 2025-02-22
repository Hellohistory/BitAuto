#!/bin/bash

# 检查是否是 root 用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "请以 root 用户或使用 sudo 执行脚本"
        exit 1
    fi
}

# 错误处理函数
handle_error() {
    echo "发生错误：$1"
    exit 1
}

# 安全执行命令
execute_with_sudo() {
    # shellcheck disable=SC2145
    sudo "$@" || handle_error "命令执行失败: $@"
}

# 检测发行版并设置适当的包管理器
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
        handle_error "未支持的 Linux 发行版"
    fi
}

# 获取公网 IP
get_public_ip() {
    echo "获取公网 IP..."
    public_ip=$(curl -s http://checkip.amazonaws.com) || handle_error "无法获取公网 IP"
    echo "公网 IP: $public_ip"
}

# 获取内网 IP
get_local_ip() {
    echo "获取内网 IP..."
    local_ip=$(hostname -I | awk '{print $1}') || handle_error "无法获取内网 IP"
    echo "内网 IP: $local_ip"
}

# 使用 dialog 创建图形界面菜单
show_menu() {
    clear
    choice=$(dialog --title "Redis 管理工具" --menu "请选择操作" 15 60 9 \
        1 "安装 Redis" \
        2 "更新 Redis" \
        3 "卸载 Redis" \
        4 "启动 Redis" \
        5 "停止 Redis" \
        6 "重启 Redis" \
        7 "修改 Redis 配置" \
        8 "查看当前 Redis 配置" \
        9 "退出" 2>&1 > /dev/tty)

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
        *) dialog --msgbox "无效选项，请重新选择。" 6 30; show_menu ;;
    esac
}

# 安装 Redis
install_redis() {
    PACKAGE_MANAGER=$(get_package_manager)

    if dpkg -l | grep -q redis-server; then
        dialog --msgbox "Redis 已经安装，跳过安装过程。" 6 30
    else
        dialog --msgbox "正在安装 Redis..." 6 30
        if [ "$PACKAGE_MANAGER" == "apt" ]; then
            execute_with_sudo apt-get update
            execute_with_sudo apt-get install -y redis-server
        elif [ "$PACKAGE_MANAGER" == "yum" ] || [ "$PACKAGE_MANAGER" == "dnf" ]; then
            execute_with_sudo yum install -y redis
        elif [ "$PACKAGE_MANAGER" == "pacman" ]; then
            execute_with_sudo pacman -S --noconfirm redis
        else
            handle_error "不支持此发行版的 Redis 安装。"
        fi
        dialog --msgbox "Redis 安装完成！" 6 30
    fi

    # 获取并显示公网和内网 IP
    get_public_ip
    get_local_ip

    show_menu
}

# 更新 Redis
update_redis() {
    PACKAGE_MANAGER=$(get_package_manager)

    dialog --msgbox "更新 Redis..." 6 30
    if [ "$PACKAGE_MANAGER" == "apt" ]; then
        execute_with_sudo apt-get update
        execute_with_sudo apt-get upgrade -y redis-server
    elif [ "$PACKAGE_MANAGER" == "yum" ] || [ "$PACKAGE_MANAGER" == "dnf" ]; then
        execute_with_sudo yum update -y redis
    elif [ "$PACKAGE_MANAGER" == "pacman" ]; then
        execute_with_sudo pacman -Syu redis
    else
        handle_error "不支持此发行版的 Redis 更新。"
    fi
    dialog --msgbox "Redis 更新完成！" 6 30
    show_menu
}

# 启动 Redis
start_redis() {
    if ! systemctl is-active --quiet redis-server; then
        dialog --msgbox "启动 Redis..." 6 30
        execute_with_sudo systemctl start redis-server
        dialog --msgbox "Redis 已启动！" 6 30
    else
        dialog --msgbox "Redis 已经在运行。" 6 30
    fi
    show_menu
}

# 停止 Redis
stop_redis() {
    if systemctl is-active --quiet redis-server; then
        dialog --msgbox "停止 Redis..." 6 30
        execute_with_sudo systemctl stop redis-server
        dialog --msgbox "Redis 已停止。" 6 30
    else
        dialog --msgbox "Redis 服务没有运行。" 6 30
    fi
    show_menu
}

# 重启 Redis
restart_redis() {
    if systemctl is-active --quiet redis-server; then
        dialog --msgbox "重启 Redis..." 6 30
        execute_with_sudo systemctl restart redis-server
        dialog --msgbox "Redis 已重启！" 6 30
    else
        dialog --msgbox "Redis 服务没有运行，正在启动..." 6 30
        execute_with_sudo systemctl start redis-server
        dialog --msgbox "Redis 已启动。" 6 30
    fi
    show_menu
}

# 修改 Redis 配置
modify_redis_config() {
    CONFIG_FILE="/etc/redis/redis.conf"
    if [ ! -f "$CONFIG_FILE" ]; then
        dialog --msgbox "Redis 配置文件不存在，请检查 Redis 是否安装。" 6 30
        show_menu
    fi

    config_choice=$(dialog --title "修改 Redis 配置" --menu "请选择要修改的配置项" 15 60 4 \
        1 "最大连接数 (maxclients)" \
        2 "最大内存使用 (maxmemory)" \
        3 "是否启用持久化 (save)" \
        4 "返回" 2>&1 > /dev/tty)

    case $config_choice in
        1) modify_maxclients ;;
        2) modify_maxmemory ;;
        3) modify_persistence ;;
        4) show_menu ;;
        *) dialog --msgbox "无效选项，请重新选择。" 6 30; modify_redis_config ;;
    esac
}

# 修改最大连接数
modify_maxclients() {
    maxclients=$(dialog --inputbox "请输入新的最大连接数 (maxclients):" 8 40 2>&1 > /dev/tty)
    execute_with_sudo sed -i "s/^# maxclients .*/maxclients $maxclients/" /etc/redis/redis.conf
    dialog --msgbox "最大连接数已修改为 $maxclients" 6 30
    show_menu
}

# 修改最大内存使用
modify_maxmemory() {
    maxmemory=$(dialog --inputbox "请输入新的最大内存使用量 (maxmemory)，例如 2gb:" 8 40 2>&1 > /dev/tty)
    execute_with_sudo sed -i "s/^# maxmemory .*/maxmemory $maxmemory/" /etc/redis/redis.conf
    dialog --msgbox "最大内存使用量已修改为 $maxmemory" 6 30
    show_menu
}

# 修改是否启用持久化
modify_persistence() {
    enable_persistence=$(dialog --yesno "启用持久化？" 6 30 && echo y || echo n)
    if [[ "$enable_persistence" == "y" ]]; then
        execute_with_sudo sed -i "s/^# save .*/save 900 1/" /etc/redis/redis.conf
        dialog --msgbox "已启用持久化" 6 30
    else
        execute_with_sudo sed -i "s/^# save .*/# save/" /etc/redis/redis.conf
        dialog --msgbox "已禁用持久化" 6 30
    fi
    show_menu
}

# 查看当前 Redis 配置
view_redis_config() {
    CONFIG_FILE="/etc/redis/redis.conf"
    if [ ! -f "$CONFIG_FILE" ]; then
        dialog --msgbox "Redis 配置文件不存在，请检查 Redis 是否安装。" 6 30
        show_menu
    fi

    dialog --textbox "$CONFIG_FILE" 20 80
    show_menu
}

# 启动菜单
check_root
show_menu
