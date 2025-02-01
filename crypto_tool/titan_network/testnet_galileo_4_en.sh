#!/usr/bin/env bash
set -e

# Capture errors and provide a prompt
trap 'echo "An error occurred. Please check the logs and try again."; exit 1' ERR

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No color

# Check the operating system distribution
check_os() {
  echo -e "${YELLOW}Detecting operating system...${NC}"
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
  elif [ -f /etc/redhat-release ]; then
    OS="rhel"
  else
    echo -e "${RED}Unable to detect the operating system. Defaulting to Ubuntu/Debian commands.${NC}"
    OS="debian"
  fi
  echo -e "${GREEN}Operating system detected: $OS${NC}"
}

# Check and install necessary dependencies
install_dependencies() {
  echo -e "${YELLOW}Checking and installing unzip, wget...${NC}"
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
      echo -e "${RED}Unsupported system: $OS. Please install unzip and wget manually.${NC}"
      exit 1
      ;;
  esac
  echo -e "${GREEN}All dependencies are installed.${NC}"
}

# Install Multipass
install_multipass() {
  echo -e "${YELLOW}Checking if Multipass is installed...${NC}"
  if command -v multipass &> /dev/null; then
    echo -e "${GREEN}Multipass is already installed. Skipping installation.${NC}"
    return
  fi
  echo -e "${YELLOW}Installing Multipass...${NC}"
  sudo snap install multipass
  echo -e "${GREEN}Multipass installation complete.${NC}"
}

# Install Titan Agent
install_titan_agent() {
  echo -e "${YELLOW}Installing Titan Agent...${NC}"
  sudo rm -rf /opt/titanagent
  sudo mkdir -p /opt/titanagent
  wget -q --show-progress -O agent-linux.zip https://pcdn.titannet.io/test4/bin/agent-linux.zip
  sudo unzip -q agent-linux.zip -d /opt/titanagent
  sudo chmod +x /opt/titanagent/agent
  rm -f agent-linux.zip
  echo -e "${GREEN}Titan Agent installation complete.${NC}"
}

# Run Titan Agent
run_titan_agent() {
  echo -e "${YELLOW}Please enter your Titan Key (input will be hidden)...${NC}"
  read -s -p "Titan Key: " user_key
  echo
  echo -e "${YELLOW}Running Titan Agent...${NC}"
  sudo /opt/titanagent/agent --working-dir=/opt/titanagent --server-url=https://test4-api.titannet.io --key="$user_key"
}

# Create systemd service
create_systemd_service() {
  echo -e "${YELLOW}Creating systemd service...${NC}"
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
  echo -e "${GREEN}Titan Agent systemd service created and enabled at startup.${NC}"
}

# Main process
check_os
install_dependencies
install_multipass
install_titan_agent
run_titan_agent
create_systemd_service

echo -e "${GREEN}All steps completed. Titan Agent is running and set to start at boot.${NC}"
