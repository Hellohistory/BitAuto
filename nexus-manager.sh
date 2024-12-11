#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 全局变量
NEXUS_HOME="$HOME/.nexus"
PROVER_ID_FILE="$NEXUS_HOME/prover-id"
SESSION_NAME="nexus-prover"
PROGRAM_DIR="$NEXUS_HOME/src/generated"
ARCH=$(uname -m)
OS=$(uname -s)
REPO_BASE="https://github.com/nexus-xyz/network-api/raw/refs/tags/0.4.2/clients/cli"

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# 检查 OpenSSL 版本
check_openssl_version() {
    if [ "$OS" = "Linux" ]; then
        if ! command -v openssl &> /dev/null; then
            log_error "未安装 OpenSSL"
            return 1
        fi

        local version
        version=$(openssl version | cut -d' ' -f2)
        local major_version
        major_version=$(echo "$version" | cut -d'.' -f1)

        if [ "$major_version" -lt 3 ]; then
            log_warning "OpenSSL 版本过低，正在升级..."
            if command -v apt &> /dev/null; then
                sudo apt update
                sudo apt install -y openssl
            elif command -v yum &> /dev/null; then
                sudo yum update -y openssl
            else
                log_error "未识别的包管理器，请手动升级 OpenSSL 至 3.0 或更高版本"
                return 1
            fi
        fi
        log_info "OpenSSL 版本检查通过"
    fi
    return 0
}

# 检查依赖
check_dependencies() {
    check_openssl_version || exit 1

    if ! command -v tmux &> /dev/null; then
        log_warning "tmux 未安装，正在安装..."
        if [ "$OS" = "Darwin" ]; then
            if ! command -v brew &> /dev/null; then
                log_error "请先安装 Homebrew: https://brew.sh"
                exit 1
            fi
            brew install tmux
        elif [ "$OS" = "Linux" ]; then
            if command -v apt &> /dev/null; then
                sudo apt update && sudo apt install -y tmux
            elif command -v yum &> /dev/null; then
                sudo yum install -y tmux
            else
                log_error "未能识别的包管理器，请手动安装 tmux"
                exit 1
            fi
        fi
    fi
}

# 设置目录结构
setup_directories() {
    mkdir -p "$PROGRAM_DIR"
    ln -sf "$PROGRAM_DIR" "$NEXUS_HOME/src/generated"
}

# 下载必要的程序文件
download_program_files() {
    local files="cancer-diagnostic fast-fib"

    for file in $files; do
        local target_path="$PROGRAM_DIR/$file"
        if [ ! -f "$target_path" ]; then
            log_warning "正在下载 $file..."
            curl -L "$REPO_BASE/src/generated/$file" -o "$target_path"
            if [ $? -eq 0 ]; then
                log_info "$file 下载完成"
                chmod +x "$target_path"
            else
                log_error "$file 下载失败"
            fi
        fi
    done
}

# 下载 Prover
download_prover() {
    local prover_path="$NEXUS_HOME/prover"
    if [ ! -f "$prover_path" ];then
        case "$OS" in
        Darwin)
            case "$ARCH" in
            x86_64)
                log_warning "下载 macOS Intel 架构 Prover..."
                curl -L "https://github.com/qzz0518/nexus-run/releases/download/v0.4.2/prover-macos-amd64" -o "$prover_path"
                ;;
            arm64)
                log_warning "下载 macOS ARM64 架构 Prover..."
                curl -L "https://github.com/qzz0518/nexus-run/releases/download/v0.4.2/prover-arm64" -o "$prover_path"
                ;;
            *)
                log_error "不支持的 macOS 架构: $ARCH"
                exit 1
                ;;
            esac
            ;;
        Linux)
            case "$ARCH" in
            x86_64)
                log_warning "下载 Linux AMD64 架构 Prover..."
                curl -L "https://github.com/qzz0518/nexus-run/releases/download/v0.4.2/prover-amd64" -o "$prover_path"
                ;;
            *)
                log_error "不支持的 Linux 架构: $ARCH"
                exit 1
                ;;
            esac
            ;;
        *)
            log_error "不支持的操作系统: $OS"
            exit 1
            ;;
        esac
        chmod +x "$prover_path"
        log_info "Prover 下载完成"
    fi
}

# 检查和设置 Prover ID
check_prover_id() {
    if [ ! -f "$PROVER_ID_FILE" ]; then
        log_warning "Prover ID 文件不存在，要求用户输入或自动生成"
        echo -e "${YELLOW}请输入您的 Prover ID${NC}"
        echo -e "${YELLOW}如果没有 Prover ID，直接按回车将自动生成${NC}"
        read -p "Prover ID > " input_id

        if [ -n "$input_id" ]; then
            echo "$input_id" > "$PROVER_ID_FILE"
            log_info "已保存 Prover ID: $input_id"
        else
            log_warning "未提供 Prover ID，将生成新的 ID"
            generate_prover_id
        fi
    fi
}

# 启动 Prover
start_prover() {
    check_prover_id
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        log_warning "Prover 已在运行中，请选择2查看运行日志"
        return
    fi
    tmux new-session -d -s "$SESSION_NAME" "./prover beta.orchestrator.nexus.xyz"
    log_info "Prover 已启动，请选择2查看运行日志"
}

# 查看运行状态
check_status() {
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        log_info "Prover 正在运行中. 正在打开日志窗口..."
        sleep 2
        tmux attach-session -t "$SESSION_NAME"
    else
        log_error "Prover 未运行"
    fi
}

# 显示 Prover ID
show_prover_id() {
    if [ -f "$PROVER_ID_FILE" ]; then
        local id
        id=$(cat "$PROVER_ID_FILE")
        log_info "当前 Prover ID: $id"
    else
        log_error "未找到 Prover ID"
    fi
}

# 停止 Prover
stop_prover() {
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        tmux kill-session -t "$SESSION_NAME"
        log_info "Prover 已停止"
    else
        log_error "Prover 未运行"
    fi
}

# 清理操作
cleanup() {
    log_warning "正在清理..."
    exit 0
}

trap cleanup SIGINT SIGTERM

# 主菜单循环
while true; do
    echo -e "\n${YELLOW}=== Nexus Prover 管理工具 ===${NC}"
    echo -e "${GREEN}原版Github: ${NC}https://github.com/qzz0518/nexus-run"
    echo -e "${GREEN}改版: ${NC}https://github.com/Hellohistory/BitAuto\n"

    echo "1. 安装并启动 Nexus"
    echo "2. 查看当前运行状态"
    echo "3. 查看 Prover ID"
    echo "4. 设置 Prover ID"
    echo "5. 停止 Nexus"
    echo "6. 退出"

    read -p "请选择操作 [1-6]: " choice
    case $choice in
        1)
            setup_directories
            check_dependencies
            download_prover
            download_program_files
            start_prover
            ;;
        2)
            check_status
            ;;
        3)
            show_prover_id
            ;;
        4)
            check_prover_id
            ;;
        5)
            stop_prover
            ;;
        6)
            log_info "感谢使用！"
            cleanup
            ;;
        *)
            log_error "无效的选择"
            ;;
    esac
done
