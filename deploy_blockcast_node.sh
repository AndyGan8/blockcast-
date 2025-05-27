#!/bin/bash

# Blockcast BEACON 一键部署与管理脚本
# 适用于 Ubuntu/Debian 系统，需 root 权限运行
# 参考文档：https://docs.blockcast.network/main

# 设置错误处理：任何命令失败则退出
set -e

# 默认配置
WORK_DIR="${BLOCKCAST_WORK_DIR:-$HOME/blockcast-beacon}"
COMPOSE_URL="${BLOCKCAST_COMPOSE_URL:-https://raw.githubusercontent.com/blockcast-network/beacon/main/docker-compose.yml}"
LOG_FILE="${WORK_DIR}/blockcast-deploy.log"

# 日志函数
log() {
    echo "[INFO] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[ERROR] $1" >&2 | tee -a "$LOG_FILE"
    exit 1
}

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    error "请以 root 权限运行此脚本（使用 sudo）"
fi

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"

# 检查依赖项：Docker 和 Docker Compose
check_dependencies() {
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
        log "Docker 已安装，版本：$(docker --version)"
    fi

    log "检查 Docker Compose 是否安装..."
    if ! command -v docker-compose &> /dev/null; then
        log "未找到 Docker Compose，正在安装..."
        curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        log "Docker Compose 安装完成，版本：$(docker-compose --version)"
    else
        log "Docker Compose 已安装，版本：$(docker-compose --version)"
    fi
}

# 验证 docker-compose.yml 文件
validate_compose_file() {
    local file="$1"
    log "验证 docker-compose.yml 文件..."
    
    # 检查文件是否存在且不为空
    if [ ! -s "$file" ]; then
        error "docker-compose.yml 文件为空或不存在"
    fi
    
    # 检查文件是否包含 "404" 错误（简单检查）
    if grep -qi "404" "$file"; then
        error "下载的 docker-compose.yml 文件包含 404 错误，请检查 COMPOSE_URL: $COMPOSE_URL"
    fi
    
    # 检查是否为有效的 YAML 文件
    if ! docker-compose -f "$file" config >/dev/null 2>&1; then
        error "docker-compose.yml 文件格式无效，请检查文件内容或 COMPOSE_URL: $COMPOSE_URL"
    fi
    
    log "docker-compose.yml 文件验证通过"
}

# 部署 Blockcast BEACON 的函数
deploy_blockcast() {
    check_dependencies

    log "创建工作目录：$WORK_DIR"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    log "下载 Docker Compose 配置文件..."
    if ! curl -L "$COMPOSE_URL" -o docker-compose.yml; then
        error "无法下载 docker-compose.yml 文件，请检查网络或 COMPOSE_URL: $COMPOSE_URL"
    fi

    # 验证下载的文件
    validate_compose_file "docker-compose.yml"

    log "启动 Blockcast BEACON..."
    if ! docker-compose up -d; then
        error "启动 Docker Compose 失败，请检查 docker-compose.yml 文件或运行 'docker-compose logs' 查看详情"
    fi

    log "检查服务状态..."
    sleep 10
    docker-compose ps

    log "获取节点注册信息..."
    REGISTRATION_INFO=$(docker-compose logs blockcastd | grep -E "Hardware ID|Challenge Key|Registration URL")
    if [ -z "$REGISTRATION_INFO" ]; then
        error "无法获取注册信息，请检查日志：docker-compose logs blockcastd"
    else
        echo "$REGISTRATION_INFO" | tee -a "$LOG_FILE"
        log "请使用上述 Hardware ID 和 Challenge Key 在 Blockcast 管理门户（https://app.blockcast.network）上注册您的节点。"
        log "您也可以直接访问 Registration URL 完成注册（需启用浏览器定位权限）。"
    fi

    log "Blockcast BEACON 部署完成！"
    log "请访问 https://app.blockcast.network/manage-nodes 检查节点状态（健康状态可能需 6 小时后显示）。"
    log "日志已保存至：$LOG_FILE"
}

# 获取注册信息的函数
get_registration_info() {
    log "获取节点注册信息..."
    if [ -d "$WORK_DIR" ]; then
        cd "$WORK_DIR"
        REGISTRATION_INFO=$(docker-compose logs blockcastd | grep -E "Hardware ID|Challenge Key|Registration URL")
        if [ -z "$REGISTRATION_INFO" ]; then
            error "无法获取注册信息，请检查日志：docker-compose logs blockcastd"
        else
            echo "$REGISTRATION_INFO" | tee -a "$LOG_FILE"
            log "请使用上述 Hardware ID 和 Challenge Key 在 Blockcast 管理门户（https://app.blockcast.network）上注册您的节点。"
            log "您也可以直接访问 Registration URL 完成注册（需启用浏览器定位权限）。"
        fi
    else
        error "Blockcast BEACON 未部署，请先运行选项 1 部署节点"
    fi
}

# 清理 Blockcast BEACON 的函数
clean_blockcast() {
    log "清理 Blockcast BEACON..."
    if [ -d "$WORK_DIR" ]; then
        cd "$WORK_DIR"
        log "停止并删除容器..."
        docker-compose down
        log "删除工作目录：$WORK_DIR"
        rm -rf "$WORK_DIR"
        log "清理完成"
    else
        log "未找到 Blockcast BEACON 部署目录，无需清理"
    fi
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
    echo "4. 获取节点注册信息"
    echo "5. 清理 Blockcast BEACON"
    echo "6. 退出"
    echo "================================="
    echo -n "请选择一个选项 [1-6]: "
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
            if [ -d "$WORK_DIR" ]; then
                cd "$WORK_DIR"
                docker-compose ps
            else
                error "Blockcast BEACON 未部署，请先运行选项 1"
            fi
            ;;
        3)
            log "查看节点日志..."
            if [ -d "$WORK_DIR" ]; then
                cd "$WORK_DIR"
                docker-compose logs
            else
                error "Blockcast BEACON 未部署，请先运行选项 1"
            fi
            ;;
        4)
            get_registration_info
            ;;
        5)
            log "开始清理 Blockcast BEACON..."
            clean_blockcast
            ;;
        6)
            log "退出程序"
            exit 0
            ;;
        *)
            log "无效选项，请选择 1-6"
            ;;
    esac
    echo -n "按 Enter 键返回主菜单..."
    read
done
