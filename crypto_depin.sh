#!/bin/bash
# 使用严格模式，确保出现错误时退出
set -euo pipefail
IFS=$'\n\t'

# 捕获中断信号，优雅退出
trap 'echo "脚本被中断，正在退出..."; exit 1' INT TERM

# 检查依赖项
command -v curl &> /dev/null || { echo "curl 未安装，请先安装 curl 后重试。"; exit 1; }

# 定义安装脚本列表，每个项格式为：关键字|描述|脚本下载地址
SCRIPT_LIST=(
    "docker|安装Docker (Docker安装脚本)|https://raw.githubusercontent.com/Hellohistory/BitAuto/refs/heads/main/docker/install_docker/docker_zh.sh"
    "Titan Network 3|安装Titan Network 3 (卡西尼测试网)|https://raw.githubusercontent.com/Hellohistory/BitAuto/refs/heads/main/crypto/titan_network/testnet_cassini_3/testnet_cassini_3_zh.sh"
    "Titan Network 4|安装Titan Network 4 (伽利略测试网)|https://raw.githubusercontent.com/Hellohistory/BitAuto/refs/heads/main/crypto/titan_network/testnet_galileo_4/testnet_galileo_4_zh.sh"
)

# 显示菜单函数
display_menu() {
    echo "=========================================="
    echo "欢迎使用 Depin 部署脚本聚合器，请选择要安装的软件："
    echo "Github地址：https://github.com/Hellohistory/BitAuto"
    echo "=========================================="
    for i in "${!SCRIPT_LIST[@]}"; do
        IFS='|' read -r key desc url <<< "${SCRIPT_LIST[$i]}"
        echo "$((i+1)). $desc"
    done
    echo "=========================================="
}

# 获取用户选择函数
get_choice() {
    local choice
    read -rp "请输入对应的软件序号（或输入 q 退出）： " choice
    # 允许用户输入退出指令
    if [[ "$choice" =~ ^[Qq]$ ]]; then
        echo "用户已退出。"
        exit 0
    fi
    if ! [[ $choice =~ ^[0-9]+$ ]]; then
        echo "输入无效，请输入数字序号。"
        exit 1
    fi
    local index=$((choice-1))
    if [ $index -lt 0 ] || [ $index -ge ${#SCRIPT_LIST[@]} ]; then
        echo "选择序号超出范围。"
        exit 1
    fi
    echo "$index"
}

# 下载并执行脚本函数
download_and_execute() {
    local key="$1"
    local url="$2"
    local desc="$3"
    local TMP_SCRIPT="/tmp/${key}_install.sh"

    # 设置 trap 清理临时文件
    trap 'rm -f "$TMP_SCRIPT"' EXIT

    echo "您选择了：$desc"
    echo "脚本下载地址：$url"
    echo "正在下载安装脚本..."
    curl -sSL "$url" -o "$TMP_SCRIPT"
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络连接或脚本地址。"
        exit 1
    fi

    chmod +x "$TMP_SCRIPT"
    echo "下载成功！"

    read -rp "是否立即执行安装脚本？(y/n): " confirm
    case "$confirm" in
        [Yy]* )
            echo "开始执行安装脚本..."
            bash "$TMP_SCRIPT"
            ret=$?
            if [ $ret -eq 0 ]; then
                echo "安装脚本执行完毕，安装成功！"
            else
                echo "安装脚本执行过程中出现错误，安装失败。"
            fi
            ;;
        * )
            echo "您选择了不立即执行。您可以稍后手动执行：bash $TMP_SCRIPT"
            ;;
    esac
}

# 主流程
main() {
    display_menu
    local index
    index=$(get_choice)
    IFS='|' read -r key desc url <<< "${SCRIPT_LIST[$index]}"
    download_and_execute "$key" "$url" "$desc"
}

main
