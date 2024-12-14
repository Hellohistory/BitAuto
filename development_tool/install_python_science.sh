#!/bin/bash

# 检查是否以root用户或具有sudo权限执行
if [ "$(id -u)" != "0" ]; then
    echo "请以root用户或使用sudo运行该脚本。"
    exit 1
fi

echo "Python 和常用科学计算库全自动安装脚本开始..."

# 1. 更新系统软件包
echo "更新系统软件包..."
sudo apt update && sudo apt -y upgrade

# 2. 安装系统依赖
echo "安装系统依赖（build-essential、curl、git、python3-venv）..."
sudo apt install -y build-essential curl git python3 python3-pip python3-venv

# 3. 检查 Python 版本
PYTHON_VERSION=$(python3 --version | awk '{print $2}')
echo "已安装的 Python 版本：$PYTHON_VERSION"

# 4. 安装常用科学计算库
echo "安装常用科学计算库..."
# 创建虚拟环境
VENV_DIR="$HOME/science_env"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"

# 安装库
pip install --upgrade pip
pip install numpy pandas scipy matplotlib seaborn scikit-learn jupyterlab ipython

# 5. 检查安装结果
echo "检查已安装的科学计算库版本："
python -c "import numpy, pandas, scipy, matplotlib, sklearn; \
    print(f'Numpy: {numpy.__version__}, Pandas: {pandas.__version__}, SciPy: {scipy.__version__}, \
    Matplotlib: {matplotlib.__version__}, scikit-learn: {sklearn.__version__}')"

# 6. 安装 JupyterLab
echo "安装 JupyterLab..."
pip install jupyterlab
echo "JupyterLab 安装完成！"
echo "启动 JupyterLab 命令：source $VENV_DIR/bin/activate && jupyter lab"

# 7. 清理和总结
echo "Python 和科学计算库安装完成！"
echo "虚拟环境已创建于：$VENV_DIR"
echo "激活虚拟环境命令：source $VENV_DIR/bin/activate"

# 提示用户激活虚拟环境后使用
echo "进入虚拟环境后，您可以运行如下命令进入 JupyterLab："
echo "jupyter lab"
