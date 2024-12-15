#!/bin/bash

# 检查是否以 root 用户或具有 sudo 权限执行
if [ "$(id -u)" != "0" ]; then
    echo "请以 root 用户或使用 sudo 运行该脚本。"
    exit 1
fi

LOG_FILE="$HOME/python_install_log.txt"
exec > >(tee -a $LOG_FILE) 2>&1
echo "安装日志将保存到：$LOG_FILE"

# 检测操作系统
if [ -f /etc/os-release ]; then
    source /etc/os-release
    OS=$ID
else
    echo "无法识别操作系统，请手动安装所需依赖。"
    exit 1
fi

# 选择包管理器
case "$OS" in
    ubuntu|debian)
        PACKAGE_MANAGER="sudo apt"
        ;;
    centos|rhel)
        PACKAGE_MANAGER="sudo yum"
        ;;
    fedora)
        PACKAGE_MANAGER="sudo dnf"
        ;;
    *)
        echo "当前系统不支持自动安装，请手动安装依赖。"
        exit 1
        ;;
esac

# 更新系统和安装基础依赖
echo "更新系统软件包..."
$PACKAGE_MANAGER update -y && $PACKAGE_MANAGER install -y build-essential curl git python3 python3-pip python3-venv

# 检查并安装特定版本的 Python
echo "是否安装特定版本的 Python？(y/n)"
read -r install_specific
if [ "$install_specific" == "y" ]; then
    echo "请输入需要安装的 Python 版本（如 3.10）："
    read -r python_version
    $PACKAGE_MANAGER install -y software-properties-common
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    $PACKAGE_MANAGER install -y python${python_version} python${python_version}-venv python${python_version}-pip
    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${python_version} 1
fi

# 创建虚拟环境
VENV_DIR="$HOME/science_env"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"

# 安装常用库
echo "安装常用科学计算库..."
libraries=(numpy pandas scipy matplotlib seaborn scikit-learn jupyterlab ipython)
for lib in "${libraries[@]}"; do
    pip install "$lib" || echo "安装 $lib 时出错，请检查网络连接。"
done

# 可选安装深度学习库
echo "是否安装深度学习库（TensorFlow 和 PyTorch）？(y/n)"
read -r install_dl
if [ "$install_dl" == "y" ]; then
    GPU_SUPPORT=$(lspci | grep -i nvidia)
    if [ -n "$GPU_SUPPORT" ]; then
        pip install tensorflow-gpu torch torchvision torchaudio
    else
        pip install tensorflow torch torchvision torchaudio
    fi
fi

# 打印结果
echo "Python 和科学计算库安装完成！"
echo "虚拟环境路径：$VENV_DIR"
echo "激活命令：source $VENV_DIR/bin/activate"
