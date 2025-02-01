#!/usr/bin/env bash
set -e

# エラーをキャッチしてヒントを提供
trap 'echo "エラーが発生しました。ログを確認し、再試行してください。"; exit 1' ERR

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # カラーなし

# OSの確認
check_os() {
  echo -e "${YELLOW}オペレーティングシステムを検出中...${NC}"
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
  elif [ -f /etc/redhat-release ]; then
    OS="rhel"
  else
    echo -e "${RED}OSを検出できません。デフォルトでUbuntu/Debianのコマンドを使用します。${NC}"
    OS="debian"
  fi
  echo -e "${GREEN}OS検出完了: $OS${NC}"
}

# 必要な依存関係を確認し、インストール
install_dependencies() {
  echo -e "${YELLOW}unzip、wgetを確認してインストール中...${NC}"
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
      echo -e "${RED}サポートされていないOS: $OS。手動でunzipとwgetをインストールしてください。${NC}"
      exit 1
      ;;
  esac
  echo -e "${GREEN}すべての依存関係がインストールされました。${NC}"
}

# Multipassのインストール
install_multipass() {
  echo -e "${YELLOW}Multipassがインストールされているか確認中...${NC}"
  if command -v multipass &> /dev/null; then
    echo -e "${GREEN}Multipassはすでにインストールされています。スキップします。${NC}"
    return
  fi
  echo -e "${YELLOW}Multipassをインストール中...${NC}"
  sudo snap install multipass
  echo -e "${GREEN}Multipassのインストールが完了しました。${NC}"
}

# Titan Agentのインストール
install_titan_agent() {
  echo -e "${YELLOW}Titan Agentをインストール中...${NC}"
  sudo rm -rf /opt/titanagent
  sudo mkdir -p /opt/titanagent
  wget -q --show-progress -O agent-linux.zip https://pcdn.titannet.io/test4/bin/agent-linux.zip
  sudo unzip -q agent-linux.zip -d /opt/titanagent
  sudo chmod +x /opt/titanagent/agent
  rm -f agent-linux.zip
  echo -e "${GREEN}Titan Agentのインストールが完了しました。${NC}"
}

# Titan Agentの実行
run_titan_agent() {
  echo -e "${YELLOW}Titan Keyを入力してください（入力は非表示になります）...${NC}"
  read -s -p "Titan Key: " user_key
  echo
  echo -e "${YELLOW}Titan Agentを実行中...${NC}"
  sudo /opt/titanagent/agent --working-dir=/opt/titanagent --server-url=https://test4-api.titannet.io --key="$user_key"
}

# systemdサービスの作成
create_systemd_service() {
  echo -e "${YELLOW}systemdサービスを作成中...${NC}"
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
  echo -e "${GREEN}Titan Agent systemdサービスが作成され、起動時に自動実行されるように設定されました。${NC}"
}

# メイン処理
check_os
install_dependencies
install_multipass
install_titan_agent
run_titan_agent
create_systemd_service

echo -e "${GREEN}すべての手順が完了しました。Titan Agentは自動的に起動し、起動時に自動実行されます。${NC}"
