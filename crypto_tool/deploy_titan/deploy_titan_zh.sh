#!/bin/bash

# Titan Docker 部署脚本
LOG_FILE="$HOME/titan_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# 配置身份码
IDENTITY_CODE="87FD8C76-B4EB-479A-86DD-0B93E8BB7B7A"

# 支持的消息日志
log_message() {
    echo "$1"
}

# 错误处理函数，提供用户选择
handle_error() {
    log_message "发生错误：$1"
    log_message "1) 重试\n2) 跳过\n3) 退出"
    read -p "请输入选项(1/2/3): " choice
    case "$choice" in
        1) return 1 ;; # 返回 1 表示重试
        2) return 0 ;; # 返回 0 表示跳过
        3) exit 1 ;; # 退出脚本
        *) log_message "无效输入，脚本退出。"
           exit 1 ;;
    esac
}

# 检查并安装 Docker
install_docker() {
    if ! command -v docker &>/dev/null; then
        log_message "Docker 未安装，正在安装 Docker..."
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
                    log_message "不支持的操作系统。"
                    return 1
                    ;;
            esac
            sudo systemctl start docker || return 1
            sudo systemctl enable docker || return 1
        else
            log_message "无法确定操作系统类型。"
            return 1
        fi
        log_message "Docker 安装完成。"
    else
        log_message "Docker 已安装，跳过安装步骤。"
    fi
}

# 清理旧节点数据
clean_old_data() {
    if [ -d "$HOME/.titanedge" ]; then
        log_message "检测到旧节点数据，是否需要清理？(y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf "$HOME/.titanedge" || return 1
            log_message "旧节点数据已清理。"
        else
            log_message "跳过旧节点数据清理。"
        fi
    else
        log_message "未检测到旧节点数据，跳过清理。"
    fi
}

# 检查 Titan 节点状态
check_titan_status() {
    if docker ps --filter "ancestor=nezha123/titan-edge" --format "{{.ID}}" | grep -q .; then
        log_message "检测到 Titan 节点正在运行，跳过部署。"
        return 0
    fi
    return 1
}

# 下载 Titan 镜像并运行节点
deploy_titan_node() {
    check_titan_status && return
    mkdir -p "$HOME/.titanedge" || return 1
    log_message "正在下载 Titan Docker 镜像..."
    if ! docker pull nezha123/titan-edge; then
        return 1
    fi
    log_message "正在运行 Titan 节点..."
    if ! docker run --network=host -d -v "$HOME/.titanedge:/root/.titanedge" nezha123/titan-edge; then
        return 1
    fi
}

# 绑定身份码
bind_identity() {
    log_message "正在绑定身份码..."
    if ! docker run --rm -it -v "$HOME/.titanedge:/root/.titanedge" nezha123/titan-edge bind --hash="$IDENTITY_CODE" \
        https://api-test1.container1.titannet.io/api/v2/device/binding; then
        return 1
    fi
    log_message "身份码绑定成功。"
}

# 主函数
main() {
    log_message "开始 Titan Docker 节点部署..."
    while ! install_docker; do
        handle_error "Docker 安装失败。"
        [ $? -eq 0 ] && break
    done
    while ! clean_old_data; do
        handle_error "清理旧数据失败。"
        [ $? -eq 0 ] && break
    done
    while ! deploy_titan_node; do
        handle_error "Titan 节点部署失败。"
        [ $? -eq 0 ] && break
    done
    while ! bind_identity; do
        handle_error "绑定身份码失败。"
        [ $? -eq 0 ] && break
    done
    log_message "Titan 节点已成功部署。"
}

# 调用主函数
main
