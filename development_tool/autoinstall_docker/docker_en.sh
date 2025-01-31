#!/bin/bash

# 检查是否以root用户或具有sudo权限执行
if [ "$(id -u)" != "0" ]; then
    echo "请以root用户或使用sudo运行该脚本。"
    exit 1
fi

echo "Docker安装脚本开始..."

# 1. 卸载已存在的Docker
echo "正在卸载已有的Docker..."
sudo apt remove -y docker-desktop
rm -r $HOME/.docker/desktop 2>/dev/null || echo "无残余目录需要清理。"
sudo rm /usr/local/bin/com.docker.cli 2>/dev/null || echo "无残余文件需要清理。"
sudo apt purge -y docker-desktop

# 更新软件包索引
echo "更新软件包索引..."
sudo apt update

# 2. 添加Docker官方源
echo "尝试添加Docker官方源..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# 3. 安装Docker
echo "尝试安装Docker (官方源)..."
sudo apt update
if sudo apt install -y docker-ce; then
    echo "Docker安装成功！(官方源)"
    docker --version
    exit 0
else
    echo "Docker安装失败！尝试切换到国内源..."
fi

# 切换到国内源
echo "选择国内镜像源:"
echo "1) 阿里源"
echo "2) 清华源"
read -p "输入选项 (1/2): " source_choice

if [ "$source_choice" == "1" ]; then
    echo "切换到阿里源..."
    curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository \
        "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
elif [ "$source_choice" == "2" ]; then
    echo "切换到清华源..."
    curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository \
        "deb [arch=amd64] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
else
    echo "无效选项，脚本退出。"
    exit 1
fi

# 重新更新软件包索引
echo "更新软件包索引..."
sudo apt update

# 尝试再次安装Docker
echo "尝试安装Docker (国内源)..."
if sudo apt install -y docker-ce; then
    echo "Docker安装成功！(国内源)"
    docker --version
    exit 0
else
    echo "Docker安装失败，请检查错误日志。"
    exit 1
fi
