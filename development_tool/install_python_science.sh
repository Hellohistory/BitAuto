#!/bin/bash

# 开启严格模式，出错立即终止
set -e

# 检查是否以 root 用户或 sudo 权限执行
if [ "$(id -u)" != "0" ]; then
    echo "请以 root 用户或使用 sudo 运行该脚本。"
    exit 1
fi

# 生成带时间戳的日志文件
LOG_FILE="$HOME/python_install_log_$(date +%F-%T).txt"
exec > >(tee -a "$LOG_FILE") 2>&1
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
        UPDATE_CMD="update -y"
        INSTALL_CMD="install -y"
        ;;
    centos|rhel)
        PACKAGE_MANAGER="sudo yum"
        UPDATE_CMD="update -y"
        INSTALL_CMD="install -y"
        ;;
    fedora)
        PACKAGE_MANAGER="sudo dnf"
        UPDATE_CMD="update -y"
        INSTALL_CMD="install -y"
        ;;
    arch)
        PACKAGE_MANAGER="sudo pacman"
        UPDATE_CMD="-Sy"
        INSTALL_CMD="-S --noconfirm"
        ;;
    opensuse*)
        PACKAGE_MANAGER="sudo zypper"
        UPDATE_CMD="refresh"
        INSTALL_CMD="install -y"
        ;;
    *)
        echo "当前系统不支持自动安装，请手动安装依赖。"
        exit 1
        ;;
esac

# 更新系统并安装基础依赖
echo "更新系统软件包..."
$PACKAGE_MANAGER $UPDATE_CMD
$PACKAGE_MANAGER $INSTALL_CMD curl git python3 python3-pip python3-venv build-essential

# 询问是否安装特定版本的 Python
read -rp "是否安装特定版本的 Python？(y/n) [默认: n] " install_specific
install_specific=${install_specific:-n}
if [ "$install_specific" == "y" ]; then
    read -rp "请输入需要安装的 Python 版本（如 3.10）： " python_version
    python_version=${python_version:-"3.10"}

    # 使用 pyenv 进行 Python 版本管理
    echo "正在安装 pyenv..."
    curl https://pyenv.run | bash

    # 配置 pyenv 环境变量
    export PATH="$HOME/.pyenv/bin:$PATH"
    eval "$(pyenv init --path)"
    eval "$(pyenv virtualenv-init -)"

    echo "安装 Python $python_version..."
    pyenv install "$python_version"
    pyenv global "$python_version"
fi

# 创建虚拟环境
VENV_DIR="$HOME/science_env"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"

# 安装常用科学计算库
echo "安装常用科学计算库..."
libraries=(numpy pandas scipy matplotlib seaborn scikit-learn ipython)
for lib in "${libraries[@]}"; do
    pip install "$lib" || echo "安装 $lib 失败，请检查网络。"
done

# 询问是否安装 Jupyter Notebook 和 JupyterLab
read -rp "是否安装 Jupyter Notebook 和 JupyterLab？(y/n) [默认: y] " install_jupyter
install_jupyter=${install_jupyter:-y}
if [ "$install_jupyter" == "y" ]; then
    echo "安装 Jupyter Notebook 和 JupyterLab..."
    pip install jupyter jupyterlab jupyter_contrib_nbextensions ipykernel

    # 启用 Jupyter Notebook 扩展
    jupyter contrib nbextension install --user
    jupyter nbextensions_configurator enable --user

    echo "Jupyter Notebook 和 JupyterLab 安装完成！"
    echo "运行 Jupyter Notebook: jupyter notebook"
    echo "运行 JupyterLab: jupyter lab"
fi

# 询问是否安装深度学习库
read -rp "是否安装深度学习库（TensorFlow 和 PyTorch）？(y/n) [默认: n] " install_dl
install_dl=${install_dl:-n}
if [ "$install_dl" == "y" ]; then
    if command -v nvidia-smi &> /dev/null; then
        echo "检测到 NVIDIA GPU，安装 GPU 版本的深度学习库..."
        pip install tensorflow-gpu torch torchvision torchaudio
    else
        echo "未检测到 NVIDIA GPU，安装 CPU 版本..."
        pip install tensorflow torch torchvision torchaudio
    fi
fi

# 询问是否安装 Conda
read -rp "是否安装 Miniconda 以支持更多数据科学工具？(y/n) [默认: n] " install_conda
install_conda=${install_conda:-n}
if [ "$install_conda" == "y" ]; then
    echo "正在安装 Miniconda..."
    curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o miniconda.sh
    bash miniconda.sh -b -p "$HOME/miniconda"
    rm miniconda.sh
    echo "Miniconda 安装完成，请手动运行 'source ~/miniconda/bin/activate' 以启用 Conda。"
fi

# 打印结果
echo "Python 和科学计算库安装完成！"
echo "虚拟环境路径：$VENV_DIR"
echo "激活命令：source $VENV_DIR/bin/activate"
