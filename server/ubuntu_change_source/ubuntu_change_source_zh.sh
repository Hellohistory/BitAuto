#!/bin/bash

# 获取 Ubuntu 版本代号，如 focal、jammy
VERSION_CODENAME=$(lsb_release -cs)

# 检测是否为 WSL
IS_WSL=false
if grep -qi microsoft /proc/version; then
    IS_WSL=true
    echo "已检测到当前环境为 WSL。"
fi

echo "系统版本代号：$VERSION_CODENAME"
echo ""

# 镜像源选项
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

echo ""
echo "你选择的 APT 源为：$NAME"
echo "开始备份原始 sources.list 文件..."

# 备份原始文件
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak

# 写入新的源
echo "正在写入新的源地址..."
sudo tee /etc/apt/sources.list > /dev/null <<EOF
deb ${MIRROR} ${VERSION_CODENAME} main restricted universe multiverse
deb ${MIRROR} ${VERSION_CODENAME}-updates main restricted universe multiverse
deb ${MIRROR} ${VERSION_CODENAME}-backports main restricted universe multiverse
deb ${MIRROR} ${VERSION_CODENAME}-security main restricted universe multiverse
EOF

# 更新索引
echo "APT 源已更换为：$NAME"
echo "正在更新软件索引，请稍候..."
sudo apt update

# 特殊提示
if $IS_WSL; then
    echo ""
    echo "提示：你正在 WSL 环境下，如遇网络慢问题，建议检查 /etc/resolv.conf 中的 DNS 配置。"
fi

echo "✅ 全部完成！APT 源现在已使用：$NAME"
