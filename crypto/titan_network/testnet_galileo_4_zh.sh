#!/usr/bin/env bash
set -e

# 捕获错误并提供提示
trap 'echo "发生错误，请检查日志并重试。"; exit 1' ERR

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 无颜色

# 检查系统发行版
check_os() {
  echo -e "${YELLOW}检测操作系统中...${NC}"
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
  elif [ -f /etc/redhat-release ]; then
    OS="rhel"
  else
    echo -e "${RED}无法检测操作系统，默认使用 Ubuntu/Debian 命令。${NC}"
    OS="debian"
  fi
  echo -e "${GREEN}系统检测完成: $OS${NC}"
}

# 检查并安装必要依赖
install_dependencies() {
  echo -e "${YELLOW}检查并安装 unzip、wget...${NC}"
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
    arch)
      sudo pacman -Sy --noconfirm unzip wget snapd
      ;;
    *)
      echo -e "${RED}不支持的系统: $OS，请手动安装 unzip 和 wget。${NC}"
      exit 1
      ;;
  esac
  echo -e "${GREEN}所有依赖已安装。${NC}"
}

# 安装 Multipass
install_multipass() {
  echo -e "${YELLOW}检查 Multipass 是否已安装...${NC}"
  if command -v multipass &> /dev/null; then
    echo -e "${GREEN}Multipass 已安装，跳过安装。${NC}"
    return
  fi
  echo -e "${YELLOW}安装 Multipass...${NC}"
  sudo snap install multipass
  echo -e "${GREEN}Multipass 安装完成。${NC}"
}

# 安装 Titan Agent
install_titan_agent() {
  echo -e "${YELLOW}安装 Titan Agent...${NC}"
  sudo rm -rf /opt/titanagent
  sudo mkdir -p /opt/titanagent
  wget -q --show-progress -O agent-linux.zip https://pcdn.titannet.io/test4/bin/agent-linux.zip
  sudo unzip -q agent-linux.zip -d /opt/titanagent
  sudo chmod +x /opt/titanagent/agent
  rm -f agent-linux.zip
  echo -e "${GREEN}Titan Agent 安装完成。${NC}"
}

# 运行 Titan Agent
run_titan_agent() {
  echo -e "${YELLOW}请输入您的 Titan Key（输入后将隐藏，不回显）...${NC}"
  read -s -p "Titan Key: " user_key
  echo
  echo -e "${YELLOW}运行 Titan Agent...${NC}"
  sudo /opt/titanagent/agent --working-dir=/opt/titanagent --server-url=https://test4-api.titannet.io --key="$user_key"
}

# 创建 systemd 服务
create_systemd_service() {
  echo -e "${YELLOW}创建 systemd 服务...${NC}"
  sudo bash -c "cat > /etc/systemd/system/titanagent.service" <<EOF
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
  echo -e "${GREEN}Titan Agent systemd 服务已创建并设置为开机自启。${NC}"
}

# 主流程
check_os
install_dependencies
install_multipass
install_titan_agent
run_titan_agent
create_systemd_service

echo -e "${GREEN}所有步骤已执行完毕，Titan Agent 已自动启动并设为开机自启。${NC}"
