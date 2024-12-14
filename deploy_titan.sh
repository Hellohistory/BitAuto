#!/bin/bash

# Titan Docker 部署脚本（优化版）
LOG_FILE="$HOME/titan_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# 配置身份码
IDENTITY_CODE="87FD8C76-B4EB-479A-86DD-0B93E8BB7B7A"

# 默认语言环境
DEFAULT_LANG="zh_CN.UTF-8"

# 支持的语言消息
log_message() {
    local message_cn="$1"
    local message_en="$2"
    if [[ "$LANG" =~ "zh_CN" ]]; then
        echo "$message_cn"
    else
        echo "$message_en"
    fi
}

# 错误处理函数
handle_error() {
    log_message "发生错误：$1，脚本即将退出。" "Error occurred: $1. Exiting script."
    exit 1
}

# 检查环境是否支持中文
ensure_locale() {
    if [[ ! "$LANG" =~ "zh_CN" ]]; then
        log_message "当前语言环境可能不支持中文，切换到中文环境..." \
                    "Current language setting may not support Chinese, switching to Chinese locale..."
        export LANG=$DEFAULT_LANG
        export LC_ALL=$DEFAULT_LANG
    fi
    if ! locale | grep -q "$DEFAULT_LANG"; then
        log_message "语言环境未完全配置，请检查系统支持。" \
                    "Locale not fully configured. Please check system language support."
    fi
}

# 检查并安装 Docker
install_docker() {
    if ! command -v docker &>/dev/null; then
        log_message "Docker 未安装，正在安装 Docker..." \
                    "Docker is not installed, installing Docker..."
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case "$ID" in
                ubuntu|debian)
                    sudo apt-get update && sudo apt-get install -y \
                        apt-transport-https ca-certificates curl software-properties-common \
                        || handle_error "依赖安装失败，退出。" "Dependency installation failed."
                    curl -fsSL https://download.docker.com/linux/$ID/gpg | \
                        sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || \
                        handle_error "获取 Docker GPG 密钥失败。" "Failed to fetch Docker GPG key."
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$ID $(lsb_release -cs) stable" | \
                        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || \
                        handle_error "Docker 源配置失败。" "Failed to configure Docker repository."
                    sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io || \
                        handle_error "Docker 安装失败。" "Failed to install Docker."
                    ;;
                centos|rhel)
                    sudo yum install -y yum-utils || handle_error "yum-utils 安装失败。" "Failed to install yum-utils."
                    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || \
                        handle_error "Docker 源配置失败。" "Failed to configure Docker repository."
                    sudo yum install -y docker-ce docker-ce-cli containerd.io || \
                        handle_error "Docker 安装失败。" "Failed to install Docker."
                    ;;
                *)
                    handle_error "不支持的操作系统。" "Unsupported operating system."
                    ;;
            esac
            sudo systemctl start docker || handle_error "Docker 启动失败。" "Failed to start Docker."
            sudo systemctl enable docker || handle_error "设置 Docker 开机启动失败。" "Failed to enable Docker at startup."
        else
            handle_error "无法确定操作系统类型。" "Unable to determine operating system type."
        fi
        log_message "Docker 安装完成。" "Docker installation completed."
    else
        log_message "Docker 已安装，跳过安装步骤。" "Docker is already installed. Skipping installation."
    fi
}

# 清理旧节点数据
clean_old_data() {
    if [ -d "$HOME/.titanedge" ]; then
        log_message "检测到旧节点数据，是否需要清理？(y/n)" \
                    "Old node data detected. Do you want to clean it? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf "$HOME/.titanedge" || handle_error "清理失败，请检查权限。" "Failed to clean old data. Check permissions."
            log_message "旧节点数据已清理。" "Old node data has been cleaned."
        else
            log_message "跳过旧节点数据清理。" "Skipped old data cleaning."
        fi
    else
        log_message "未检测到旧节点数据，跳过清理。" "No old node data detected. Skipping cleaning."
    fi
}

# 下载 Titan 镜像并运行节点
deploy_titan_node() {
    mkdir -p "$HOME/.titanedge" || handle_error "存储卷目录创建失败。" "Failed to create storage volume directory."
    log_message "正在下载 Titan Docker 镜像..." "Downloading Titan Docker image..."
    if ! docker pull nezha123/titan-edge; then
        handle_error "镜像下载失败。" "Failed to download Docker image."
    fi
    log_message "正在运行 Titan 节点..." "Running Titan node..."
    if ! docker run --network=host -d -v "$HOME/.titanedge:/root/.titanedge" nezha123/titan-edge; then
        handle_error "节点运行失败。" "Failed to run the Titan node."
    fi
}

# 绑定身份码
bind_identity() {
    log_message "正在绑定身份码..." "Binding identity code..."
    if ! docker run --rm -it -v "$HOME/.titanedge:/root/.titanedge" nezha123/titan-edge bind --hash="$IDENTITY_CODE" \
        https://api-test1.container1.titannet.io/api/v2/device/binding; then
        handle_error "绑定身份码失败。" "Failed to bind identity code."
    fi
    log_message "身份码绑定成功。" "Identity code bound successfully."
}

# 主函数
main() {
    log_message "开始 Titan Docker 节点部署..." "Starting Titan Docker node deployment..."
    ensure_locale
    install_docker
    clean_old_data
    deploy_titan_node
    bind_identity
    log_message "Titan 节点已成功部署。" "Titan node has been successfully deployed."
}

# 调用主函数
main
