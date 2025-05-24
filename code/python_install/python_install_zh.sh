#!/usr/bin/env bash
set -euo pipefail

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
export PYENV_GITHUB_REPO="https://github.com/pyenv/pyenv.git"
export PYENV_GITEE_REPO="https://gitee.com/mirrors/pyenv.git"
export PYTHON_BUILD_MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/python"
REQUIRED_VERSION="3.9.13"

install_dependencies() {
    echo "📦 安装系统依赖 (包括 fzf)..."
    sudo apt update
    sudo apt install -y make build-essential libssl-dev zlib1g-dev \
        libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
        libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
        libffi-dev liblzma-dev git fzf
}

ensure_pyenv() {
    if ! command -v pyenv &> /dev/null; then
        echo "🔧 未检测到 pyenv，开始安装..."
        install_dependencies
        echo "🌐 克隆 pyenv..."
        if ! git clone "$PYENV_GITHUB_REPO" "$PYENV_ROOT"; then
            echo "⚠️ GitHub 克隆失败，尝试 Gitee..."
            git clone "$PYENV_GITEE_REPO" "$PYENV_ROOT"
        fi
        cat <<'EOF' >> ~/.bashrc
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)"
eval "$(pyenv init -)"
EOF
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init --path)"
        eval "$(pyenv init -)"
    else
        echo "🔄 检测到 pyenv，尝试更新..."
        install_dependencies
        if [ -d "$PYENV_ROOT/plugins/pyenv-update" ]; then
            pyenv update
        else
            echo "🌐 GitHub 更新 pyenv..."
            if ! git -C "$PYENV_ROOT" pull; then
                echo "⚠️ GitHub 更新失败，使用 Gitee 镜像..."
                git -C "$PYENV_ROOT" remote set-url origin "$PYENV_GITEE_REPO"
                git -C "$PYENV_ROOT" pull
                git -C "$PYENV_ROOT" remote set-url origin "$PYENV_GITHUB_REPO"
            fi
        fi
    fi
}

get_installed_versions() {
    mapfile -t INSTALLED < <(pyenv versions --bare)
}

choose_versions_fzf() {
    echo
    echo "📋 获取可安装的 Python 版本列表（已安装版本 ✅ 标记）"
    mapfile -t USER_SELECTED < <(
        pyenv install --list \
        | grep -E '^[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' \
        | sed 's/^[[:space:]]*//' \
        | while read -r ver; do
            if printf '%s\n' "${INSTALLED[@]}" | grep -qx "$ver"; then
                echo "$ver ✅ 已安装"
            else
                echo "$ver"
            fi
        done \
        | fzf --multi \
              --prompt="Python 版本选择 > " \
              --marker='✓' \
              --header="空格选择，回车确认；已安装版本带 ✅" \
              --info=inline \
              --color=marker:yellow,prompt:green,header:cyan \
              --bind=space:toggle \
        | sed 's/ ✅ 已安装//'
    )

    PYTHON_VERSIONS=("${USER_SELECTED[@]}")

    # 强制加入 3.9.13，如果未选择
    if [[ ! " ${PYTHON_VERSIONS[*]} " =~ " ${REQUIRED_VERSION} " ]]; then
        echo "🔐 强制加入必须安装版本 $REQUIRED_VERSION"
        PYTHON_VERSIONS+=("$REQUIRED_VERSION")
    fi

    if [ "${#PYTHON_VERSIONS[@]}" -eq 0 ]; then
        echo "❌ 未选择任何版本，退出。"
        exit 1
    fi
}

install_versions() {
    for version in "${PYTHON_VERSIONS[@]}"; do
        echo "▶️ 安装 Python $version ..."
        pyenv install --skip-existing -v "$version"
    done
}

choose_pip_source() {
    echo
    echo "🌐 请选择是否配置 pip 国内源（建议配置加速安装）"
    SOURCE=$(printf "TUNA 清华源\nAliyun 阿里云\nNo 不更换" | \
        fzf --prompt="pip 源选择 > " \
            --header="请选择 pip 镜像源用于新版本 Python" \
            --height=10 --border --color=prompt:green,header:cyan)

    case "$SOURCE" in
        "TUNA 清华源")
            PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
            ;;
        "Aliyun 阿里云")
            PIP_INDEX_URL="https://mirrors.aliyun.com/pypi/simple/"
            ;;
        "No 不更换")
            PIP_INDEX_URL=""
            ;;
    esac
}

configure_pip_source() {
    if [ -z "$PIP_INDEX_URL" ]; then
        echo "⏩ 跳过 pip 源配置。"
        return
    fi
    for version in "${PYTHON_VERSIONS[@]}"; do
        PIP_CONF_PATH="$PYENV_ROOT/versions/$version/pip.conf"
        echo "📄 配置 pip 源 for Python $version"
        cat > "$PIP_CONF_PATH" <<EOF
[global]
index-url = $PIP_INDEX_URL
EOF
    done
}

choose_global_version() {
    echo
    echo "🧠 请选择 pyenv 默认 Python 版本（global）"
    mapfile -t SELECTED < <(
        printf '%s\n' "${PYTHON_VERSIONS[@]}" \
        | fzf --prompt="默认版本 > " \
              --header="选择一个 Python 版本作为默认 pyenv global" \
              --height=10 --border --color=prompt:green,header:cyan \
              --no-multi
    )

    if [ -z "${SELECTED[0]:-}" ]; then
        echo "⚠️ 未选择默认版本，强制设置为 $REQUIRED_VERSION"
        GLOBAL_VERSION="$REQUIRED_VERSION"
    else
        GLOBAL_VERSION="${SELECTED[0]}"
    fi

    echo "⚙️ 设置 pyenv global 为 $GLOBAL_VERSION"
    pyenv global "$GLOBAL_VERSION"
}

main() {
    ensure_pyenv
    get_installed_versions
    choose_versions_fzf
    install_versions
    choose_pip_source
    configure_pip_source
    choose_global_version
    echo "🎉 安装及配置完成！默认 Python: $(python --version)"
}

main "$@"
