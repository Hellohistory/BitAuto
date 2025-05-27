#!/bin/bash

# 检查是否以 root 用户执行
if [ "$EUID" -ne 0 ]; then
    echo "错误：请以 root 用户运行此脚本。"
    exit 1
fi

# 提示用户输入服务名称，默认值为 harbor
read -p "请输入服务名称（默认：harbor）: " SERVICE_NAME
SERVICE_NAME=${SERVICE_NAME:-harbor}

# 提示用户输入服务描述，默认值为 Harbor 镜像仓库
read -p "请输入服务描述（默认：Harbor 镜像仓库）: " SERVICE_DESCRIPTION
SERVICE_DESCRIPTION=${SERVICE_DESCRIPTION:-Harbor 镜像仓库}

# 提示用户输入 Harbor 版本，默认值为 v2.13.1
read -p "请输入 Harbor 版本（默认：v2.13.1）: " HARBOR_VERSION
HARBOR_VERSION=${HARBOR_VERSION:-v2.13.1}

# 提示用户输入工作目录，默认值为 /opt/harbor
read -p "请输入工作目录（默认：/opt/harbor）: " WORKING_DIRECTORY
WORKING_DIRECTORY=${WORKING_DIRECTORY:-/opt/harbor}

# 提示用户输入日志文件路径，默认值为 /var/log/harbor.log
read -p "请输入日志文件路径（默认：/var/log/harbor.log）: " LOG_FILE
LOG_FILE=${LOG_FILE:-/var/log/harbor.log}

# 设置 Harbor 下载链接
HARBOR_DOWNLOAD_URL="https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/harbor-online-installer-${HARBOR_VERSION}.tgz"

# 创建日志文件目录和文件
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# 创建 Systemd 服务单元文件
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=${SERVICE_DESCRIPTION}
After=docker.service

[Service]
ExecStart=${WORKING_DIRECTORY}/install.sh >> ${LOG_FILE} 2>&1
WorkingDirectory=${WORKING_DIRECTORY}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 在线安装 Harbor
install_harbor_online() {
    echo "开始在线安装 Harbor..."

    # 创建工作目录
    mkdir -p "$WORKING_DIRECTORY"

    # 下载 Harbor 安装包
    curl -LJ "$HARBOR_DOWNLOAD_URL" -o /tmp/harbor.tgz
    if [ $? -ne 0 ]; then
        echo "错误：下载 Harbor 安装包失败。"
        exit 1
    fi

    # 解压安装包
    tar -zxvf /tmp/harbor.tgz -C "$WORKING_DIRECTORY"
    if [ $? -ne 0 ]; then
        echo "错误：解压 Harbor 安装包失败。"
        exit 1
    fi

    # 赋予安装脚本可执行权限
    chmod +x "${WORKING_DIRECTORY}/install.sh"

    # 重载 Systemd 配置
    systemctl daemon-reload

    # 启动 Harbor 服务
    systemctl start "$SERVICE_NAME"

    echo "Harbor 服务安装成功！"
}

# 离线安装 Harbor
install_harbor_offline() {
    echo "开始离线安装 Harbor..."

    # 检查离线安装文件是否存在
    if [ -f "harbor-online-installer-${HARBOR_VERSION}.tgz" ]; then
        # 创建工作目录
        mkdir -p "$WORKING_DIRECTORY"

        # 复制离线安装文件到工作目录
        cp "harbor-online-installer-${HARBOR_VERSION}.tgz" "$WORKING_DIRECTORY"

        # 解压安装包
        tar -zxvf "${WORKING_DIRECTORY}/harbor-online-installer-${HARBOR_VERSION}.tgz" -C "$WORKING_DIRECTORY"
        if [ $? -ne 0 ]; then
            echo "错误：解压 Harbor 安装包失败。"
            exit 1
        fi

        # 赋予安装脚本可执行权限
        chmod +x "${WORKING_DIRECTORY}/install.sh"

        # 重载 Systemd 配置
        systemctl daemon-reload

        # 启动 Harbor 服务
        systemctl start "$SERVICE_NAME"

        echo "Harbor 服务安装成功！"
    else
        echo "错误：未找到离线安装文件 'harbor-online-installer-${HARBOR_VERSION}.tgz'，请将其放置在当前目录。"
        exit 1
    fi
}

# 卸载 Harbor
uninstall_harbor() {
    echo "开始卸载 Harbor..."

    # 停止 Harbor 服务
    systemctl stop "$SERVICE_NAME"

    # 禁用开机自启
    systemctl disable "$SERVICE_NAME"

    # 删除工作目录
    rm -rf "$WORKING_DIRECTORY"

    # 删除 Systemd 服务文件
    rm -f "$SERVICE_FILE"

    # 重载 Systemd 配置
    systemctl daemon-reload

    echo "Harbor 服务卸载成功！"
}

# 启用开机自启
enable_autostart() {
    systemctl enable "$SERVICE_NAME"
    echo "已启用 Harbor 服务的开机自启。"
}

# 禁用开机自启
disable_autostart() {
    systemctl disable "$SERVICE_NAME"
    echo "已禁用 Harbor 服务的开机自启。"
}

# 显示操作菜单
echo "请选择操作："
echo "1. 在线安装 Harbor"
echo "2. 离线安装 Harbor"
echo "3. 卸载 Harbor"
echo "4. 启用开机自启"
echo "5. 禁用开机自启"
read -p "请输入选项编号（1-5）： " option

# 根据用户选择执行相应操作
case $option in
    1) install_harbor_online ;;
    2) install_harbor_offline ;;
    3) uninstall_harbor ;;
    4) enable_autostart ;;
    5) disable_autostart ;;
    *) echo "无效的选项，请输入 1 到 5 之间的数字。" ;;
esac
