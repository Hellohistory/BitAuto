#!/usr/bin/env bash
set -e

# 捕获错误并提供提示
trap 'echo "发生错误，请检查日志并重试。"; exit 1' ERR

# 检查系统发行版
check_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
  else
    echo "无法检测操作系统，默认使用 Ubuntu/Debian 命令。"
    OS="debian"
  fi
}

# 检查并安装必要依赖
install_dependencies() {
  echo "检查并安装 unzip、wget..."
  case $OS in
    ubuntu|debian)
      sudo apt update && sudo apt install -y unzip wget snapd
      ;;
    fedora)
      sudo dnf install -y unzip wget snapd
      ;;
    centos|rhel)
      sudo yum install -y unzip wget snapd
      ;;
    *)
      echo "不支持的系统: $OS，请手动安装 unzip 和 wget。"
      exit 1
      ;;
  esac
  echo "所有依赖已安装。"
}

# 安装 Multipass
install_multipass() {
  if ! command -v multipass &> /dev/null; then
    echo "安装 Multipass..."
    sudo snap install multipass
  else
    echo "Multipass 已安装，跳过安装。"
  fi
}

# 安装 Titan Agent
install_titan_agent() {
  echo "安装 Titan Agent..."
  sudo rm -rf /opt/titanagent
  sudo mkdir -p /opt/titanagent
  wget -q -O agent-linux.zip https://pcdn.titannet.io/test4/bin/agent-linux.zip
  sudo unzip -q agent-linux.zip -d /opt/titanagent
  sudo chmod +x /opt/titanagent/agent
  rm -f agent-linux.zip
  echo "Titan Agent 安装完成。"
}

# 创建 systemd 服务
create_systemd_service() {
  echo "创建 systemd 服务..."
  cat <<EOF | sudo tee /etc/systemd/system/titanagent.service > /dev/null
[Unit]
Description=Titan Agent Service
After=network.target

[Service]
Type=simple
ExecStart=/opt/titanagent/agent --working-dir=/opt/titanagent --server-url=https://test4-api.titannet.io --key=YOUR_KEY
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable titanagent
  echo "Titan Agent systemd 服务已创建并设置为开机自启。"
}

# 运行 Titan Agent
run_titan_agent() {
  echo "运行 Titan Agent..."
  sudo systemctl start titanagent
  echo "Titan Agent 已启动。"
}

# 主流程
check_os
install_dependencies
install_multipass
install_titan_agent
create_systemd_service
run_titan_agent

echo "所有步骤已执行完毕，Titan Agent 已自动启动并设为开机自启。"
