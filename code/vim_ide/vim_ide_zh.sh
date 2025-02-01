#!/bin/bash

#========================================================
# Neovim IDE 环境安装/配置脚本（Linux/Darwin, 交互式版）
#========================================================
# 主要功能：
# 1. 交互式询问是否执行系统升级、是否备份旧配置等
# 2. 自动安装/升级 Neovim、Node.js、Python3、Pyright 等依赖
# 3. 使用 vim-plug 管理插件，自动安装常用插件
# 4. 基于 Coc.nvim 的智能补全环境（示例配置 Pyright）
#========================================================

#-----------------------------
#         全局变量区
#-----------------------------
LOG_FILE="/tmp/nvim_install.log"
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No Color

NVIM_CONFIG_DIR="$HOME/.config/nvim"
INIT_VIM="$NVIM_CONFIG_DIR/init.vim"
COC_SETTINGS="$NVIM_CONFIG_DIR/coc-settings.json"

UPDATE_SYSTEM="n"   # 是否更新系统软件包
BACKUP_OLD_INIT="n" # 是否备份旧的 Neovim 配置文件
INSTALL_NODE="n"    # 是否自动安装/更新 Node.js 及 Pyright

#-----------------------------
#         函数定义区
#-----------------------------

# 日志输出重定向
prepare_logging() {
    exec > >(tee -i "$LOG_FILE") 2>&1
    echo "安装日志将记录到 $LOG_FILE"
}

# 检查是否为 root 或具备 sudo 权限
check_root_or_sudo() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请以 root 用户或使用 sudo 运行该脚本。${NC}"
        exit 1
    fi
}

# 交互式选项获取
ask_user_preferences() {
    echo -e "${GREEN}是否需要更新系统软件包并升级？ (Y/n)${NC}"
    read -r ans
    if [[ "$ans" =~ ^[Yy]$ || -z "$ans" ]]; then
        UPDATE_SYSTEM="y"
    fi

    echo -e "${GREEN}是否需要备份旧的 Neovim 配置文件（init.vim）？ (Y/n)${NC}"
    read -r ans
    if [[ "$ans" =~ ^[Yy]$ || -z "$ans" ]]; then
        BACKUP_OLD_INIT="y"
    fi

    echo -e "${GREEN}是否需要安装/更新 Node.js 及 Pyright？ (Y/n)${NC}"
    read -r ans
    if [[ "$ans" =~ ^[Yy]$ || -z "$ans" ]]; then
        INSTALL_NODE="y"
    fi
}

# 根据系统类型判定包管理器
detect_package_manager() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt >/dev/null 2>&1; then
            PACKAGE_MANAGER="apt"
        else
            echo -e "${RED}未检测到 apt 包管理器，请确认您的 Linux 发行版。${NC}"
            exit 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew >/dev/null 2>&1; then
            PACKAGE_MANAGER="brew"
        else
            echo -e "${RED}未检测到 Homebrew，请先安装 Homebrew。${NC}"
            exit 1
        fi
    else
        echo -e "${RED}当前系统不支持自动安装，请手动安装 Neovim 和依赖。${NC}"
        exit 1
    fi
}

# 更新系统并安装依赖
install_nvim_and_dependencies() {
    echo "准备安装 Neovim 和相关依赖..."

    # 是否先升级系统
    if [ "$UPDATE_SYSTEM" == "y" ]; then
        echo "更新系统并升级软件包..."
        if [ "$PACKAGE_MANAGER" == "apt" ]; then
            sudo apt update && sudo apt -y upgrade
            sudo apt install -y neovim curl git python3 python3-pip
        elif [ "$PACKAGE_MANAGER" == "brew" ]; then
            brew update && brew upgrade
            brew install neovim curl git python3
        fi
    else
        # 不执行系统升级，只单纯安装 neovim / python / git 等
        if [ "$PACKAGE_MANAGER" == "apt" ]; then
            sudo apt install -y neovim curl git python3 python3-pip
        elif [ "$PACKAGE_MANAGER" == "brew" ]; then
            brew install neovim curl git python3
        fi
    fi

    # 安装 pynvim，以支持 Python 相关功能
    pip install --upgrade pip
    pip install --upgrade pynvim
}

# 安装或更新 Node.js & Pyright
install_or_update_node_pyright() {
    if [ "$INSTALL_NODE" == "y" ]; then
        # 检查 Node.js
        if ! command -v node &>/dev/null; then
            echo "未检测到 Node.js，开始安装 Node.js..."
            if [ "$PACKAGE_MANAGER" == "apt" ]; then
                curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
                sudo apt install -y nodejs
            elif [ "$PACKAGE_MANAGER" == "brew" ]; then
                brew install node
            fi
        else
            # 如果 Node.js 已安装，考虑是否更新
            echo "系统已检测到 Node.js，可根据需要自行更新。"
        fi

        # 安装或更新 Pyright
        if command -v npm &>/dev/null; then
            echo "安装或更新 Pyright..."
            npm install -g pyright
        else
            echo -e "${RED}未检测到 npm，请确认 Node.js 安装是否成功。${NC}"
        fi
    fi
}

# 配置 vim-plug 插件管理器
configure_vim_plug() {
    echo "配置 vim-plug 插件管理器..."
    if [ ! -d "$NVIM_CONFIG_DIR/autoload" ]; then
        mkdir -p "$NVIM_CONFIG_DIR/autoload"
    fi

    curl -fLo "$NVIM_CONFIG_DIR/autoload/plug.vim" --create-dirs \
         https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
}

# 备份并生成 init.vim
setup_init_vim() {
    # 如果已存在旧的 init.vim，判断是否需要备份
    if [ -f "$INIT_VIM" ]; then
        if [ "$BACKUP_OLD_INIT" == "y" ]; then
            local timestamp
            timestamp=$(date +%Y%m%d%H%M%S)
            mv "$INIT_VIM" "${INIT_VIM}.bak_${timestamp}"
            echo "检测到旧的 init.vim 文件，已备份至 ${INIT_VIM}.bak_${timestamp}"
        else
            echo "检测到旧的 init.vim 文件，但选择不备份，直接覆盖。"
        fi
    fi

    echo "创建新的 init.vim..."
    cat > "$INIT_VIM" <<EOF
" 基础设置
set number              " 显示行号
set relativenumber      " 显示相对行号
set tabstop=4           " 制表符宽度
set shiftwidth=4        " 自动缩进宽度
set expandtab           " 将 Tab 转为空格
set cursorline          " 高亮当前行
set clipboard=unnamedplus " 使用系统剪贴板
set termguicolors       " 启用 24 位颜色

" 使用 vim-plug 管理插件
call plug#begin('~/.vim/plugged')

" 常用插件
Plug 'preservim/nerdtree'             " 文件树
Plug 'junegunn/fzf', { 'do': './install --bin' }  " 模糊查找
Plug 'junegunn/fzf.vim'               " fzf 集成
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'} " 语法高亮
Plug 'neoclide/coc.nvim', {'branch': 'release'}  " 代码补全
Plug 'vim-airline/vim-airline'        " 状态栏美化
Plug 'vim-airline/vim-airline-themes' " 状态栏主题

call plug#end()

" 键位映射
nmap <C-n> :NERDTreeToggle<CR>       " Ctrl+n 打开/关闭文件树

EOF
}

# 配置 Coc.nvim
setup_coc() {
    echo "配置 Coc.nvim 的语言服务器..."
    cat > "$COC_SETTINGS" <<EOF
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
}

# 自动安装插件
install_nvim_plugins() {
    echo "启动 Neovim 并安装插件..."
    nvim +PlugInstall +qall || {
        echo -e "${RED}Neovim 插件安装失败，请检查网络或 vim-plug 配置。${NC}"
        exit 1
    }
}

#-----------------------------
#       主流程执行区
#-----------------------------
main() {
    prepare_logging
    check_root_or_sudo
    detect_package_manager
    ask_user_preferences
    install_nvim_and_dependencies
    install_or_update_node_pyright
    configure_vim_plug
    setup_init_vim
    setup_coc
    install_nvim_plugins

    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}Neovim IDE 环境安装/配置 完成！${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo "配置文件路径：$INIT_VIM"
    echo "Coc 设置路径：$COC_SETTINGS"
    echo "启动命令：nvim"
    echo
    echo "常用快捷键："
    echo "  1. Ctrl+n：打开/关闭文件树（NERDTree）"
    echo "  2. :FZF   ：全局模糊查找文件"
    echo "  3. Coc.nvim 提供自动代码补全，示例里安装了 Pyright"
    echo
    echo "详细日志位于：$LOG_FILE"
}

main
