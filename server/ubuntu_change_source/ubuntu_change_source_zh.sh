#!/bin/bash

# 检测系统信息
VERSION_CODENAME=$(lsb_release -cs)
IS_WSL=false
if grep -qi microsoft /proc/version; then
    IS_WSL=true
    echo "已检测到当前环境为 WSL。"
fi

echo "系统版本代号：$VERSION_CODENAME"
echo ""

# ========== 1. 选择 APT 源 ==========
echo "请选择一个 Ubuntu 软件源（默认：清华大学）"
echo "1) 清华大学"
echo "2) 中科大"
echo "3) 阿里云"
echo "4) 华为云"
echo "5) 网易"
read -p "输入序号 [1-5，默认1]：" APT_CHOICE
APT_CHOICE=${APT_CHOICE:-1}

case "$APT_CHOICE" in
    1) MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"; NAME="清华大学" ;;
    2) MIRROR="https://mirrors.ustc.edu.cn/ubuntu/"; NAME="中科大" ;;
    3) MIRROR="http://mirrors.aliyun.com/ubuntu/"; NAME="阿里云" ;;
    4) MIRROR="https://mirrors.huaweicloud.com/repository/ubuntu/"; NAME="华为云" ;;
    5) MIRROR="http://mirrors.163.com/ubuntu/"; NAME="网易" ;;
    *) echo "无效输入，退出。"; exit 1 ;;
esac

echo "你选择的 APT 源为：$NAME"

# 备份并替换 sources.list
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
sudo tee /etc/apt/sources.list > /dev/null <<EOF
deb ${MIRROR} ${VERSION_CODENAME} main restricted universe multiverse
deb ${MIRROR} ${VERSION_CODENAME}-updates main restricted universe multiverse
deb ${MIRROR} ${VERSION_CODENAME}-backports main restricted universe multiverse
deb ${MIRROR} ${VERSION_CODENAME}-security main restricted universe multiverse
EOF

echo "APT 源已更换为：$NAME"
sudo apt update

# WSL 提示
if $IS_WSL; then
    echo "提示：你正在 WSL 环境下，如遇网络慢问题，建议手动优化 /etc/resolv.conf DNS 设置。"
fi

# ========== 2. 是否更换 pip 源 ==========
echo ""
read -p "是否需要更换 pip 源为国内镜像？(y/N): " CHANGE_PIP
CHANGE_PIP=${CHANGE_PIP:-n}

if [[ $CHANGE_PIP == [yY] ]]; then
    echo "请选择 pip 镜像源："
    echo "1) 清华大学"
    echo "2) 阿里云"
    echo "3) 中科大"
    echo "4) 豆瓣"
    read -p "输入序号 [1-4，默认1]：" PIP_CHOICE
    PIP_CHOICE=${PIP_CHOICE:-1}

    case "$PIP_CHOICE" in
        1) PIP_MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple" ;;
        2) PIP_MIRROR="https://mirrors.aliyun.com/pypi/simple" ;;
        3) PIP_MIRROR="https://pypi.mirrors.ustc.edu.cn/simple" ;;
        4) PIP_MIRROR="https://pypi.douban.com/simple" ;;
        *) echo "无效输入，取消 pip 源更换。"; exit 1 ;;
    esac

    mkdir -p ~/.pip
    tee ~/.pip/pip.conf > /dev/null <<EOF
[global]
index-url = $PIP_MIRROR
trusted-host = $(echo $PIP_MIRROR | awk -F/ '{print $3}')
EOF

    echo "pip 源已更换为：$PIP_MIRROR"
else
    echo "已跳过 pip 源配置。"
fi

echo ""
echo "全部配置完成！你现在可以更快速地进行开发和安装了。"
