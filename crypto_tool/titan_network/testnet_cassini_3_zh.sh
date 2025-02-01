#!/bin/bash

# Titan Docker 部署脚本

# 错误处理函数，提供用户选择
handle_error() {
    echo "发生错误：$1"
    echo -e "1) 重试\n2) 跳过\n3) 退出"
    read -p "请输入选项(1/2/3): " choice
    case "$choice" in
        1) return 1 ;; # 返回 1 表示重试
        2) return 0 ;; # 返回 0 表示跳过
        3) exit 1 ;; # 退出脚本
        *) echo "无效输入，脚本退出。"
           exit 1 ;;
    esac
}

# 检查并安装 Docker（使用外部脚本）
install_docker_external() {
    if ! command -v docker &>/dev/null; then
        echo "Docker 未安装，正在下载并安装 Docker..."
        if ! bash <(curl -sSL https://raw.githubusercontent.com/Hellohistory/BitAuto/refs/heads/main/development_tool/autoinstall_docker/docker_zh.sh); then
            return 1
        fi
        echo "Docker 安装完成。"
    else
        echo "Docker 已安装，跳过安装步骤。"
    fi
}

# 清理旧节点数据
clean_old_data() {
    if [ -d "$HOME/.titanedge" ]; then
        echo "检测到旧节点数据，是否需要清理？(y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf "$HOME/.titanedge" || return 1
            echo "旧节点数据已清理。"
        else
            echo "跳过旧节点数据清理。"
        fi
    else
        echo "未检测到旧节点数据，跳过清理。"
    fi
}

# 检查 Titan 节点状态
check_titan_status() {
    if docker ps --filter "ancestor=nezha123/titan-edge" --format "{{.ID}}" | grep -q .; then
        echo "检测到 Titan 节点正在运行，跳过部署。"
        return 0
    fi
    return 1
}

# 下载 Titan 镜像并运行节点
deploy_titan_node() {
    check_titan_status && return
    mkdir -p "$HOME/.titanedge" || return 1
    echo "正在下载 Titan Docker 镜像..."
    if ! docker pull nezha123/titan-edge; then
        return 1
    fi
    echo "正在运行 Titan 节点..."
    if ! docker run --network=host -d -v "$HOME/.titanedge:/root/.titanedge" nezha123/titan-edge; then
        return 1
    fi
}

# 绑定身份码
bind_identity() {
    echo "请输入您的绑定身份码："
    read -p "绑定身份码: " IDENTITY_CODE
    echo "正在绑定身份码..."
    if ! docker run --rm -it \
         -v "$HOME/.titanedge:/root/.titanedge" \
         nezha123/titan-edge \
         bind --hash="$IDENTITY_CODE" https://api-test1.container1.titannet.io/api/v2/device/binding; then
        return 1
    fi
    echo "身份码绑定成功。"
}

# 升级提示及选择
upgrade_titan_node() {
    echo "检测到新版本的 Titan 节点，是否需要升级？(y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "开始升级 Titan 节点..."
        # 停止并移除旧容器
        docker stop $(docker ps --filter "ancestor=nezha123/titan-edge" --format "{{.ID}}") || return 1
        docker rm $(docker ps --filter "ancestor=nezha123/titan-edge" --format "{{.ID}}") || return 1
        # 拉取新镜像并运行
        if ! docker pull nezha123/titan-edge; then
            return 1
        fi
        if ! docker run --network=host -d -v "$HOME/.titanedge:/root/.titanedge" nezha123/titan-edge; then
            return 1
        fi
        echo "Titan 节点升级完成。"
    else
        echo "跳过 Titan 节点升级。"
    fi
}

# 主函数
main() {
    echo "开始 Titan Docker 节点部署..."

    # 安装 Docker
    while ! install_docker_external; do
        handle_error "Docker 安装失败。"
        if [ $? -ne 1 ]; then
            break
        fi
    done

    # 确认 Docker 已安装
    if ! command -v docker &>/dev/null; then
        echo "Docker 未成功安装，无法继续部署。"
        exit 1
    fi

    # 清理旧数据
    while ! clean_old_data; do
        handle_error "清理旧数据失败。"
        if [ $? -ne 1 ]; then
            break
        fi
    done

    # 部署 Titan 节点
    while ! deploy_titan_node; do
        handle_error "Titan 节点部署失败。"
        if [ $? -ne 1 ]; then
            break
        fi
    done

    # 绑定身份码
    while ! bind_identity; do
        handle_error "绑定身份码失败。"
        if [ $? -ne 1 ]; then
            break
        fi
    done

    # 升级 Titan 节点
    while ! upgrade_titan_node; do
        handle_error "Titan 节点升级失败。"
        if [ $? -ne 1 ]; then
            break
        fi
    done

    echo "Titan 节点已成功部署或升级。"
}

# 调用主函数
main
