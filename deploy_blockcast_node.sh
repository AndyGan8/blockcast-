#!/bin/bash

# Blockcast BEACON 一键部署与管理脚本
# 适用于 Ubuntu/Debian 系统，需 root 权限运行
# 参考文档：https://docs.blockcast.network/main

# 设置错误处理：任何命令失败则退出
set -e

# 日志函数
log() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    error "请以 root 权限运行此脚本（使用 sudo）"
fi

# 部署 Blockcast BEACON 的函数
deploy_blockcast() {
    # 检查依赖项：Docker 和 Docker Compose
    log "检查 Docker 是否安装..."
    if ! command -v docker &> /dev/null; then
        log "未找到 Docker，正在安装..."
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        apt-get update
        apt-get install -y docker-ce
        log "Docker 安装完成"
    else
        log "Docker 已安装"
    fi

    # 检查 Docker Compose
    log "检查 Docker Compose 是否安装..."
    if ! command -v docker-compose &> /dev/null; then
        log "未找到 Docker Compose，正在安装..."
        curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        log "Docker Compose 安装完成"
    else
        log "Docker Compose 已安装"
    fi

    # 创建工作目录
    WORK_DIR="$HOME/blockcast-beacon"
    log "创建工作目录：$WORK_DIR"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    # 下载 Blockcast BEACON 的 Docker Compose 配置文件
    COMPOSE_URL="https://raw.githubusercontent.com/blockcast-network/beacon/main/docker-compose.yml"
    log "下载 Docker Compose 配置文件..."
    curl -L "$COMPOSE_URL" -o docker-compose.yml || error "无法下载 docker-compose.yml 文件"

    # 启动 Blockcast BEACON
    log "启动 Blockcast BEACON..."
    docker-compose up -d || error "启动 Docker Compose 失败"

    # 检查服务状态
    log "检查服务状态..."
    sleep 10
    docker-compose ps

    # 获取注册信息
    log "获取节点注册信息..."
    REGISTRATION_INFO=$(docker-compose logs blockcastd | grep -E "Hardware ID|Challenge Key|Registration URL")
    if [ -z "$REGISTRATION_INFO" ]; then
        error "无法获取注册信息，请检查日志：docker-compose logs blockcastd"
    else
        echo "$REGISTRATION_INFO"
        log "请使用上述 Hardware ID 和 Challenge Key 在 Blockcast 管理门户（https://app.blockcast.network）上注册您的节点。"
        log "您也可以直接访问 Registration URL 完成注册（需启用浏览器定位权限）。"
    fi

    log "Blockcast BEACON 部署完成！"
    log "请访问 https://app.blockcast.network/manage-nodes 检查节点状态（健康状态可能需 6 小时后显示）。"
    log "如需查看日志，运行：docker-compose logs"
}

# 显示主菜单
show_menu() {
    clear
    echo "================================="
    echo "       Blockcast 主菜单         "
    echo "================================="
    echo "1. 部署 Blockcast BEACON 节点"
    echo "2. 查看节点状态"
    echo "3. 查看节点日志"
    echo "4. 退出"
    echo "================================="
    echo -n "请选择一个选项 [1-4]: "
}

# 主循环
while true; do
    show_menu
    read choice
    case $choice in
        1)
            log "开始部署 Blockcast BEACON 节点..."
            deploy_blockcast
            ;;
        2)
            log "检查节点状态..."
            if [ -d "$HOME/blockcast-beacon" ]; then
                cd "$HOME/blockcast-beacon"
                docker-compose ps
            else
                error "Blockcast BEACON 未部署，请先运行选项 1"
            fi
            ;;
        3)
            log "查看节点日志..."
            if [ -d "$HOME/blockcast-beacon" ]; then
                cd "$HOME/blockcast-beacon"
                docker-compose logs
            else
                error "Blockcast BEACON 未部署，请先运行选项 1"
            fi
            ;;
        4)
            log "退出程序"
            exit 0
            ;;
        *)
            log "无效选项，请选择 1-4"
            ;;
    esac
    echo -n "按 Enter 键返回主菜单..."
    read
done
