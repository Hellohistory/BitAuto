#!/bin/bash

# 检查是否以 root 用户或具有 sudo 权限执行
if [ "$(id -u)" != "0" ]; then
    echo "请以 root 用户或使用 sudo 运行该脚本。"
    exit 1
fi

echo "Vim/Neovim IDE 环境全自动安装脚本开始..."

# 日志记录
LOG_FILE="/tmp/nvim_install.log"
exec > >(tee -i "$LOG_FILE") 2>&1
echo "安装日志将记录到 $LOG_FILE"

# 颜色定义
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# 检测系统类型
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PACKAGE_MANAGER="apt"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    PACKAGE_MANAGER="brew"
else
    echo -e "${RED}当前系统不支持自动安装，请手动安装 Neovim 和依赖。${NC}"
    exit 1
fi

# 更新系统软件包
echo "更新系统软件包..."
if [ "$PACKAGE_MANAGER" == "apt" ]; then
    sudo apt update && sudo apt -y upgrade
elif [ "$PACKAGE_MANAGER" == "brew" ]; then
    brew update && brew upgrade
fi

# 安装 Neovim 和必要依赖
echo "安装 Neovim 和必要依赖..."
if [ "$PACKAGE_MANAGER" == "apt" ]; then
    sudo apt install -y neovim curl git python3 python3-pip
elif [ "$PACKAGE_MANAGER" == "brew" ]; then
    brew install neovim curl git python3
fi

# 检查 Node.js 是否安装
if ! command -v node &> /dev/null; then
    echo "未检测到 Node.js，开始安装 Node.js..."
    if [ "$PACKAGE_MANAGER" == "apt" ]; then
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt install -y nodejs
    elif [ "$PACKAGE_MANAGER" == "brew" ]; then
        brew install node
    fi
fi

# 配置插件管理器（vim-plug）
echo "配置 Neovim 插件管理器 vim-plug..."
NVIM_CONFIG_DIR="$HOME/.config/nvim"
if [ ! -d "$NVIM_CONFIG_DIR" ]; then
    mkdir -p "$NVIM_CONFIG_DIR"
fi

curl -fLo "$NVIM_CONFIG_DIR/autoload/plug.vim" --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

# 创建 Neovim 配置文件
echo "创建 Neovim 配置文件..."
cat > "$NVIM_CONFIG_DIR/init.vim" <<EOF
" 基础设置
set number              " 显示行号
set relativenumber      " 显示相对行号
set tabstop=4           " 制表符宽度
set shiftwidth=4        " 自动缩进宽度
set expandtab           " 将 tab 转为空格
set cursorline          " 高亮当前行
set clipboard=unnamedplus " 使用系统剪贴板
set termguicolors       " 启用 24 位颜色

" 使用 vim-plug 管理插件
call plug#begin('~/.vim/plugged')

" 常用插件
Plug 'preservim/nerdtree'            " 文件树
Plug 'junegunn/fzf', { 'do': './install --bin' } " 模糊查找
Plug 'junegunn/fzf.vim'              " fzf 集成
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'} " 语法高亮
Plug 'neoclide/coc.nvim', {'branch': 'release'} " 代码补全
Plug 'vim-airline/vim-airline'       " 状态栏美化
Plug 'vim-airline/vim-airline-themes' " 状态栏主题

call plug#end()

" 键位映射
nmap <C-n> :NERDTreeToggle<CR>       " Ctrl+n 打开/关闭文件树
EOF

# 启动 Neovim 并安装插件
echo "启动 Neovim 并安装插件..."
nvim +PlugInstall +qall

# 配置 Coc.nvim 的语言服务器
echo "配置 Coc.nvim 的语言服务器..."
cat > "$NVIM_CONFIG_DIR/coc-settings.json" <<EOF
{
    "languageserver": {
        "pyright": {
            "command": "pyright-langserver",
            "args": ["--stdio"],
            "filetypes": ["python"],
            "settings": {}
        }
    }
}
EOF

# 安装 Python 的支持
pip install pynvim

# 备份旧配置文件
if [ -f "$NVIM_CONFIG_DIR/init.vim" ]; then
    mv "$NVIM_CONFIG_DIR/init.vim" "$NVIM_CONFIG_DIR/init.vim.bak"
    echo "检测到旧的 init.vim 文件，已备份至 init.vim.bak"
fi

# 提示完成
echo -e "${GREEN}Neovim IDE 环境安装完成！${NC}"
echo "配置文件路径：$NVIM_CONFIG_DIR/init.vim"
echo "启动 Neovim 命令：nvim"
echo "您可以使用以下快捷键和功能："
echo "1. Ctrl+n：打开/关闭文件树（NERDTree）"
echo "2. :FZF：全局模糊查找文件"
echo "3. 自动代码补全由 Coc.nvim 提供，支持 Python 等语言"

echo "详细日志文件位于：$LOG_FILE"
