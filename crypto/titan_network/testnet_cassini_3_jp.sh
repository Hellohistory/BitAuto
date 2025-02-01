#!/bin/bash

# Titan Docker デプロイスクリプト

# エラーハンドリング関数、ユーザーに選択肢を提供
handle_error() {
    echo "エラーが発生しました: $1"
    echo -e "1) 再試行\n2) スキップ\n3) 終了"
    read -p "オプションを入力してください (1/2/3): " choice
    case "$choice" in
        1) return 1 ;; # 1 を返すと再試行
        2) return 0 ;; # 0 を返すとスキップ
        3) exit 1 ;; # スクリプトを終了
        *) echo "無効な入力です、スクリプトを終了します。"
           exit 1 ;;
    esac
}

# Docker のインストールチェックとインストール（外部スクリプトを使用）
install_docker_external() {
    if ! command -v docker &>/dev/null; then
        echo "Docker はインストールされていません。ダウンロードしてインストールします..."
        if ! bash <(curl -sSL https://raw.githubusercontent.com/Hellohistory/BitAuto/refs/heads/main/development_tool/autoinstall_docker/docker_jp.sh); then
            return 1
        fi
        echo "Docker のインストールが完了しました。"
    else
        echo "Docker はすでにインストールされています。インストール手順をスキップします。"
    fi
}

# 古いノードデータのクリーンアップ
clean_old_data() {
    if [ -d "$HOME/.titanedge" ]; then
        echo "古いノードデータが検出されました。クリーンアップしますか？(y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf "$HOME/.titanedge" || return 1
            echo "古いノードデータをクリーンアップしました。"
        else
            echo "古いノードデータのクリーンアップをスキップしました。"
        fi
    else
        echo "古いノードデータは検出されませんでした。スキップします。"
    fi
}

# Titan ノードの状態確認
check_titan_status() {
    if docker ps --filter "ancestor=nezha123/titan-edge" --format "{{.ID}}" | grep -q .; then
        echo "Titan ノードが既に実行中です。デプロイをスキップします。"
        return 0
    fi
    return 1
}

# Titan イメージのダウンロードとノードの実行
deploy_titan_node() {
    check_titan_status && return
    mkdir -p "$HOME/.titanedge" || return 1
    echo "Titan Docker イメージをダウンロードしています..."
    if ! docker pull nezha123/titan-edge; then
        return 1
    fi
    echo "Titan ノードを実行しています..."
    if ! docker run --network=host -d -v "$HOME/.titanedge:/root/.titanedge" nezha123/titan-edge; then
        return 1
    fi
}

# 身分コードをバインド
bind_identity() {
    echo "バインドする身分コードを入力してください："
    read -p "身分コード: " IDENTITY_CODE
    echo "身分コードをバインドしています..."
    if ! docker run --rm -it \
         -v "$HOME/.titanedge:/root/.titanedge" \
         nezha123/titan-edge \
         bind --hash="$IDENTITY_CODE" https://api-test1.container1.titannet.io/api/v2/device/binding; then
        return 1
    fi
    echo "身分コードがバインドされました。"
}

# アップグレードの通知と選択
upgrade_titan_node() {
    echo "新しいバージョンの Titan ノードが検出されました。アップグレードしますか？(y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Titan ノードをアップグレードしています..."
        # 古いコンテナを停止して削除
        docker stop $(docker ps --filter "ancestor=nezha123/titan-edge" --format "{{.ID}}") || return 1
        docker rm $(docker ps --filter "ancestor=nezha123/titan-edge" --format "{{.ID}}") || return 1
        # 新しいイメージをプルして実行
        if ! docker pull nezha123/titan-edge; then
            return 1
        fi
        if ! docker run --network=host -d -v "$HOME/.titanedge:/root/.titanedge" nezha123/titan-edge; then
            return 1
        fi
        echo "Titan ノードのアップグレードが完了しました。"
    else
        echo "Titan ノードのアップグレードをスキップしました。"
    fi
}

# メイン関数
main() {
    echo "Titan Docker ノードのデプロイを開始します..."

    # Docker をインストール
    while ! install_docker_external; do
        handle_error "Docker のインストールに失敗しました。"
        if [ $? -ne 1 ]; then
            break
        fi
    done

    # Docker がインストールされているか確認
    if ! command -v docker &>/dev/null; then
        echo "Docker は正常にインストールされませんでした。デプロイを続行できません。"
        exit 1
    fi

    # 古いデータをクリーンアップ
    while ! clean_old_data; do
        handle_error "古いデータのクリーンアップに失敗しました。"
        if [ $? -ne 1 ]; then
            break
        fi
    done

    # Titan ノードをデプロイ
    while ! deploy_titan_node; do
        handle_error "Titan ノードのデプロイに失敗しました。"
        if [ $? -ne 1 ]; then
            break
        fi
    done

    # 身分コードをバインド
    while ! bind_identity; do
        handle_error "身分コードのバインドに失敗しました。"
        if [ $? -ne 1 ]; then
            break
        fi
    done

    # Titan ノードをアップグレード
    while ! upgrade_titan_node; do
        handle_error "Titan ノードのアップグレードに失敗しました。"
        if [ $? -ne 1 ]; then
            break
        fi
    done

    echo "Titan ノードは正常にデプロイまたはアップグレードされました。"
}

# メイン関数を呼び出す
main
