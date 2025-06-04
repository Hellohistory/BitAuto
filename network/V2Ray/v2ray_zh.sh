#!/usr/bin/env bash
# shellcheck disable=SC2268

# 原脚本安装的文件符合文件系统层次结构标准：https://wiki.linuxfoundation.org/lsb/fhs
# 原脚本项目的地址是：https://github.com/v2fly/fhs-install-v2ray
# 原脚本的地址是：https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh
# 如果脚本执行错误，请访问：https://github.com/v2fly/fhs-install-v2ray/issues

# 现脚本项目地址是：https://github.com/Hellohistory/BitAuto
# 现脚本的地址是：https://raw.githubusercontent.com/Hellohistory/BitAuto/refs/heads/network/V2Ray/v2ray_zh.sh

# 颜色定义
red=$(tput setaf 1)
green=$(tput setaf 2)
aoi=$(tput setaf 4)
reset=$(tput sgr0)

curl() {
  $(type -P curl) -L -q --retry 5 --retry-delay 10 --retry-max-time 60 "$@"
}

systemd_cat_config() {
  # 检查当前系统是否支持 systemd 的 cat-config 命令
  if systemd-analyze --help | grep -qw 'cat-config'; then
    systemd-analyze --no-pager cat-config "$@"
    echo
  else
    # 如果不支持，手动输出配置文件内容
    # shellcheck disable=SC2154
    echo "${aoi}~~~~~~~~~~~~~~~~"
    cat "$@" "$1".d/*
    echo "${aoi}~~~~~~~~~~~~~~~~"
    # shellcheck disable=SC2154
    echo "${red}警告: ${green}当前操作系统的 systemd 版本过低。"
    echo "${red}警告: ${green}请考虑升级 systemd 或操作系统版本。${reset}"
    echo
  fi
}

check_if_running_as_root() {
  # 检查是否以 root 用户运行
  if [[ "$UID" -ne '0' ]]; then
    echo "警告: 当前执行脚本的用户不是 root 用户，可能会遇到权限不足的问题。"
    read -r -p "是否继续以当前用户执行？[y/n] " cont_without_been_root
    if [[ x"${cont_without_been_root:0:1}" = x'y' ]]; then
      echo "继续以当前用户安装..."
    else
      echo "未以 root 用户执行，退出..."
      exit 1
    fi
  fi
}

identify_the_operating_system_and_architecture() {
  # 判断操作系统和硬件架构
  if [[ "$(uname)" == 'Linux' ]]; then
    case "$(uname -m)" in
      'i386' | 'i686')
        MACHINE='32'
        ;;

      'amd64' | 'x86_64')
        MACHINE='64'
        ;;

      'armv5tel')
        MACHINE='arm32-v5'
        ;;

      'armv6l')
        MACHINE='arm32-v6'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
        ;;

      'armv7' | 'armv7l')
        MACHINE='arm32-v7a'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
        ;;

      'armv8' | 'aarch64')
        MACHINE='arm64-v8a'
        ;;

      'mips')
        MACHINE='mips32'
        ;;

      'mipsle')
        MACHINE='mips32le'
        ;;

      'mips64')
        MACHINE='mips64'
        ;;

      'mips64le')
        MACHINE='mips64le'
        ;;

      'ppc64')
        MACHINE='ppc64'
        ;;

      'ppc64le')
        MACHINE='ppc64le'
        ;;

      'riscv64')
        MACHINE='riscv64'
        ;;

      's390x')
        MACHINE='s390x'
        ;;

      *)
        echo "错误: 不支持此架构。"
        exit 1
        ;;
    esac
    if [[ ! -f '/etc/os-release' ]]; then
      echo "错误: 不支持使用过时的 Linux 发行版。"
      exit 1
    fi
    if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup && [[ "$(type -P systemctl)" ]]; then
      true
    elif [[ -d /run/systemd/system ]] || grep -q systemd <(ls -l /sbin/init); then
      true
    else
      echo "错误: 只支持使用 systemd 的 Linux 发行版。"
      exit 1
    fi
    if [[ "$(type -P apt)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='apt -y --no-install-recommends install'
      PACKAGE_MANAGEMENT_REMOVE='apt purge'
      package_provide_tput='ncurses-bin'
    elif [[ "$(type -P dnf)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='dnf -y install'
      PACKAGE_MANAGEMENT_REMOVE='dnf remove'
      package_provide_tput='ncurses'
    elif [[ "$(type -P yum)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='yum -y install'
      PACKAGE_MANAGEMENT_REMOVE='yum remove'
      package_provide_tput='ncurses'
    elif [[ "$(type -P zypper)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='zypper install -y --no-recommends'
      PACKAGE_MANAGEMENT_REMOVE='zypper remove'
      package_provide_tput='ncurses-utils'
    elif [[ "$(type -P pacman)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='pacman -Syu --noconfirm'
      PACKAGE_MANAGEMENT_REMOVE='pacman -Rsn'
      package_provide_tput='ncurses'
    else
      echo "错误: 当前操作系统的包管理器不受支持。"
      exit 1
    fi
  else
    echo "错误: 当前操作系统不支持。"
    exit 1
  fi
}

# 交互式参数选择
choose_action() {
  # 提供操作选项供用户选择
  echo "请选择操作:"
  echo "1. 安装V2Ray"
  echo "2. 升级V2Ray"
  echo "3. 移除V2Ray"
  echo "4. 检查更新"
  echo "5. 显示帮助"
  read -p "请输入数字(1-5): " action

  case $action in
    1)
      install_v2ray
      ;;
    2)
      check_update
      ;;
    3)
      remove_v2ray
      ;;
    4)
      check_update
      ;;
    5)
      show_help
      ;;
    *)
      echo "无效选项，请输入1到5之间的数字。"
      choose_action
      ;;
  esac
}

# 显示帮助信息
show_help() {
  # 显示如何使用脚本
  echo "使用方法：请选择操作并输入相应的数字"
  echo "1: 安装V2Ray"
  echo "2: 升级V2Ray"
  echo "3: 移除V2Ray"
  echo "4: 检查更新"
  echo "5: 显示帮助"
}

main() {
  # 执行检查和安装任务
  check_if_running_as_root
  identify_the_operating_system_and_architecture

  # 调用交互式操作选择函数
  choose_action
}

main "$@"
