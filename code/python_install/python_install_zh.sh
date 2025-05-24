#!/usr/bin/env bash
set -euo pipefail

# -----------------------
# 环境变量和镜像源配置
# -----------------------
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
export PYENV_GITHUB_REPO="https://mirrors.tuna.tsinghua.edu.cn/git/pyenv.git"
export PYTHON_BUILD_MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/python"

# -----------------------
# 安装系统依赖：pyenv 所需 + fzf
# -----------------------
install_dependencies() {
    echo "📦 安装系统依赖 (包括 fzf)..."
    sudo apt update
    sudo apt install -y make build-essential libssl-dev zlib1g-dev \
        libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
        libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
        libffi-dev liblzma-dev git fzf
}

# -----------------------
# 确保 pyenv 已就绪
# -----------------------
ensure_pyenv() {
    if ! command -v pyenv &> /dev/null; then
        echo "🔧 未检测到 pyenv，开始安装 pyenv..."
        install_dependencies
        git clone "$PYENV_GITHUB_REPO" "$PYENV_ROOT"
        cat <<'EOF' >> ~/.bashrc
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)"
eval "$(pyenv init -)"
EOF
        # 立即生效配置
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init --path)"
        eval "$(pyenv init -)"
    else
        echo "🔄 检测到 pyenv，尝试更新 pyenv..."
        install_dependencies    # 确保 fzf 也被安装
        if [ -d "$PYENV_ROOT/plugins/pyenv-update" ]; then
            pyenv update
        else
            git -C "$PYENV_ROOT" pull
        fi
    fi
}

# -----------------------
# 用 fzf 交互式选择版本
# -----------------------
choose_versions_fzf() {
    echo
    echo "📋 获取可安装的 Python 版本列表，并启动 fzf 多选…"
    mapfile -t PYTHON_VERSIONS < <(
        pyenv install --list \
        | grep -E '^[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' \
        | sed 's/^[[:space:]]*//' \
        | fzf --multi --prompt="请选择要安装的 Python 版本 (空格选，回车确认): "
    )
    if [ "${#PYTHON_VERSIONS[@]}" -eq 0 ]; then
        echo "❌ 未选择任何版本，退出。"
        exit 1
    fi
}

# -----------------------
# 安装选中版本
# -----------------------
install_versions() {
    for version in "${PYTHON_VERSIONS[@]}"; do
        echo "▶️ 安装 Python $version ..."
        pyenv install --skip-existing -v "$version"
    done
}

# -----------------------
# 主流程入口
# -----------------------
main() {
    ensure_pyenv
    choose_versions_fzf
    install_versions
    echo "✅ 安装完成！"
}

main "$@"
