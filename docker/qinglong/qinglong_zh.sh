#!/bin/bash
set -euo pipefail

# 全局配置
IMAGE_NAME="whyour/qinglong:latest"
CONTAINER_NAME="qinglong"
CONTAINER_PORT=5700
MAX_RETRY=3

# 读取有效的用户输入（y/n）
read_yes_no() {
    local prompt="$1"
    local input
    while true; do
        read -p "$prompt" input
        case "$input" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
            *) echo "请输入 y 或 n." ;;
        esac
    done
}

# 读取青龙暴露端口（默认5700）
read_exposed_port() {
    local input_port
    read -p "请输入青龙暴露的端口 (默认5700): " input_port
    if [ -z "$input_port" ]; then
        EXPOSED_PORT=5700
    else
        EXPOSED_PORT=$input_port
    fi
}

# 检查 Docker 是否安装
check_docker_installed() {
    if command -v docker &>/dev/null; then
        echo "✅ Docker 已安装"
        return 0
    else
        echo "❌ Docker 未安装，请先安装 Docker"
        echo "参考安装文档：https://docs.docker.com/engine/install/"
        return 1
    fi
}

# 检查 Docker 是否在运行
check_docker_running() {
    if docker info &>/dev/null; then
        echo "✅ Docker 正在运行"
        return 0
    else
        echo "⚠️ Docker 已安装但未运行"
        return 1
    fi
}

# 启动 Docker 服务（支持 systemctl 和 service）
start_docker_service() {
    echo "尝试启动 Docker 服务..."
    if command -v systemctl &>/dev/null; then
        if sudo systemctl start docker; then
            echo "✅ Docker 服务启动成功（systemctl）"
            return 0
        fi
    elif command -v service &>/dev/null; then
        if sudo service docker start; then
            echo "✅ Docker 服务启动成功（service）"
            return 0
        fi
    fi
    echo "❌ Docker 启动失败，请手动检查"
    return 1
}

# 验证代理地址格式 (简单验证)
validate_proxy() {
    local proxy="$1"
    if [[ "$proxy" =~ ^https?://.+ ]]; then
        return 0
    else
        return 1
    fi
}

# 设置 Docker 代理
set_docker_proxy() {
    local proxy
    read -p "请输入 Docker HTTP/HTTPS 代理地址（例如 http://your.proxy.address:port）： " proxy
    if [ -z "$proxy" ]; then
        echo "代理地址不能为空，取消设置代理。"
        return 1
    fi
    if ! validate_proxy "$proxy"; then
        echo "代理地址格式不正确，请使用正确的格式（例如 http://your.proxy.address:port）"
        return 1
    fi
    echo "正在配置 Docker 代理为 $proxy ..."
    local proxy_conf="/etc/systemd/system/docker.service.d/http-proxy.conf"
    if [ -f "$proxy_conf" ]; then
        echo "检测到已有 Docker 代理配置"
        if ! read_yes_no "是否覆盖现有的代理配置？(y/n): "; then
            echo "保留现有代理配置，取消设置代理。"
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
    echo "✅ Docker 代理配置完成并服务已重启"
}

# 拉取镜像、自动启动青龙容器，并输出青龙面板访问地址
deploy_qinglong() {
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRY ]; do
        echo "🚀 开始拉取青龙镜像（尝试次数: $((retry_count+1))）..."
        if docker pull "$IMAGE_NAME"; then
            echo "✅ 青龙镜像拉取成功！"
            # 若存在同名容器则先移除
            if [ "$(docker ps -a -q -f name="^${CONTAINER_NAME}$")" ]; then
                echo "检测到已有名为 ${CONTAINER_NAME} 的容器，正在移除旧容器..."
                docker rm -f "$CONTAINER_NAME"
            fi
            echo "正在启动青龙容器..."
            docker run -dit --name "$CONTAINER_NAME" -p "${EXPOSED_PORT}:${CONTAINER_PORT}" "$IMAGE_NAME"
            # 获取公网IP（需确保curl已安装）
            PUBLIC_IP=$(curl -s ifconfig.me)
            echo "✅ 青龙容器启动成功！"
            echo "青龙面板访问地址: http://${PUBLIC_IP}:${EXPOSED_PORT}"
            return 0
        else
            echo "❌ 拉取镜像失败（尝试次数: $((retry_count+1))），可能是网络问题导致。"
            if read_yes_no "是否需要设置 Docker 代理并重新尝试拉取？(y/n): "; then
                if ! set_docker_proxy; then
                    echo "代理设置失败或取消，退出拉取镜像流程。"
                    return 1
                fi
            else
                echo "用户选择不设置代理，退出拉取镜像流程。"
                return 1
            fi
        fi
        retry_count=$((retry_count+1))
    done
    echo "❌ 超过最大重试次数，拉取镜像失败。"
    return 1
}

# 主流程
main() {
    echo "🔍 检测 Docker 环境..."
    check_docker_installed || exit 1

    if ! check_docker_running; then
        if read_yes_no "Docker 未运行，是否启动 Docker 服务？(y/n): "; then
            start_docker_service || exit 1
            if ! check_docker_running; then
                echo "❌ Docker 服务仍未启动，请手动检查。"
                exit 1
            fi
        else
            echo "用户取消启动 Docker 服务，脚本退出。"
            exit 0
        fi
    fi

    read_exposed_port
    deploy_qinglong
}

main
