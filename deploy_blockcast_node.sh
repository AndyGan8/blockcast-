#!/bin/bash

# Blockcast BEACON 一键部署与管理脚本
# 适用于 Ubuntu/Debian 系统，需 root 权限运行
# 参考文档：https://docs.blockcast.network/main

# 设置错误处理：任何命令失败则退出
set -e

# 默认配置
WORK_DIR="${BLOCKCAST_WORK_DIR:-$HOME/blockcast-beacon}"
REPO_URL="https://github.com/Blockcast/beacon-docker-compose.git"
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

# 检查依赖项：Docker、Docker Compose 和 Git
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

    log "启动 Docker 服务..."
    systemctl start docker
    systemctl enable docker >/dev/null 2>&1
    log "Docker 服务已启动"

    log "检查 Docker Compose 是否安装..."
    if ! command -v docker-compose &> /dev/null; then
        log "未找到 Docker Compose，正在安装..."
        curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        log "Docker Compose 安装完成，版本：$(docker-compose --version)"
    else
        log "Docker Compose 已安装，版本：$(docker-compose --version)"
    fi

    log "检查 Git 是否安装..."
    if ! command -v git &> /dev/null; then
        log "未找到 Git，正在安装..."
        apt-get update
        apt-get install -y git
        log "Git 安装完成，版本：$(git --version)"
    else
        log "Git 已安装，版本：$(git --version)"
    fi
}

# 验证 docker-compose.yml 文件
validate_compose_file() {
    local file="$1"
    log "验证 docker-compose.yml 文件..."
    
    if [ ! -s "$file" ]; then
        error "docker-compose.yml 文件为空或不存在"
    fi
    
    if ! docker-compose -f "$file" config >/dev/null 2>&1; then
        error "docker-compose.yml 文件格式无效，请检查文件内容"
    fi
    
    log "docker-compose.yml 文件验证通过"
}

# 检查并创建缺失的配置文件
check_config_files() {
    log "检查必要的配置文件..."
    cd "$WORK_DIR/beacon-docker-compose"
    
    # 检查 gateway.mconfig
    GATEWAY_CONFIG="/var/opt/magma/configs/gateway.mconfig"
    if ! docker compose exec -T blockcastd test -f "$GATEWAY_CONFIG" >/dev/null 2>&1; then
        log "未找到 $GATEWAY_CONFIG，正在创建默认配置文件..."
        docker compose exec -T blockcastd mkdir -p /var/opt/magma/configs
        docker compose exec -T blockcastd bash -c "echo '{}' > $GATEWAY_CONFIG" || error "无法创建 $GATEWAY_CONFIG"
        log "已创建默认 $GATEWAY_CONFIG"
    else
        log "$GATEWAY_CONFIG 已存在"
    fi

    # 检查 beacond.yml
    BEACOND_CONFIG="/etc/magma/cdn/beacond.yml"
    if ! docker compose exec -T beacond test -f "$BEACOND_CONFIG" >/dev/null 2>&1; then
        log "未找到 $BEACOND_CONFIG，正在创建默认配置文件..."
        docker compose exec -T beacond mkdir -p /etc/magma/cdn
        docker compose exec -T beacond bash -c "echo '{}' > $BEACOND_CONFIG" || error "无法创建 $BEACOND_CONFIG"
        log "已创建默认 $BEACOND_CONFIG"
    else
        log "$BEACOND_CONFIG 已存在"
    fi
}

# 部署 Blockcast BEACON 的函数
deploy_blockcast() {
    check_dependencies

    log "创建工作目录：$WORK_DIR"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    log "克隆 Blockcast BEACON 代码库..."
    if [ -d "beacon-docker-compose" ]; then
        log "代码库目录已存在，更新代码..."
        cd beacon-docker-compose
        git pull origin main || error "无法更新代码库，请检查网络或仓库地址: $REPO_URL"
    else
        if ! git clone "$REPO_URL"; then
            error "无法克隆代码库，请检查网络或仓库地址: $REPO_URL"
        fi
        cd beacon-docker-compose
    fi

    validate_compose_file "docker-compose.yml"

    log "启动 Blockcast BEACON..."
    if ! docker compose up -d; then
        error "启动 Docker Compose 失败，请检查 docker-compose.yml 文件或运行 'docker compose logs' 查看详情"
    fi

    log "检查服务状态..."
    sleep 10
    docker compose ps

    log "检查并创建必要的配置文件..."
    check_config_files

    log "获取节点注册信息..."
    get_registration_info
}

# 获取注册信息的函数（优化部分）
get_registration_info() {
    log "获取节点注册信息..."
    if [ -d "$WORK_DIR/beacon-docker-compose" ]; then
        cd "$WORK_DIR/beacon-docker-compose"
        log "执行 blockcastd init 获取 Hardware ID 和 Challenge Key..."
        
        # 重试机制，最多尝试 3 次，每次间隔 5 秒
        RETRY_COUNT=3
        for ((i=1; i<=RETRY_COUNT; i++)); do
            REGISTRATION_INFO=$(docker compose exec -T blockcastd blockcastd init 2>&1)
            if [ $? -eq 0 ]; then
                echo "$REGISTRATION_INFO" | tee -a "$LOG_FILE"
                log "请使用上述 Hardware ID 和 Challenge Key 在 Blockcast 管理门户（https://app.blockcast.network）上注册您的节点。"
                log "如果输出中包含 Registration URL，您也可以直接访问该 URL 完成注册（需启用浏览器定位权限）。"
                return 0
            else
                log "第 $i 次尝试执行 'blockcastd init' 失败，重试中..."
                sleep 5
            fi
        done
        error "执行 'docker compose exec blockcastd blockcastd init' 失败，请检查日志：docker compose logs blockcastd"
    else
        error "Blockcast BEACON 未部署，请先运行选项 1 部署节点"
    fi
}

# 清理 Blockcast BEACON 的函数
clean_blockcast() {
    log "清理 Blockcast BEACON..."
    if [ -d "$WORK_DIR/beacon-docker-compose" ]; then
        cd "$WORK_DIR/beacon-docker-compose"
        log "停止并删除容器..."
        docker compose down
        cd "$WORK_DIR"
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
            if [ -d "$WORK_DIR/beacon-docker-compose" ]; then
                cd "$WORK_DIR/beacon-docker-compose"
                docker compose ps
            else
                error "Blockcast BEACON 未部署，请先运行选项 1"
            fi
            ;;
        3)
            log "查看节点日志..."
            if [ -d "$WORK_DIR/beacon-docker-compose" ]; then
                cd "$WORK_DIR/beacon-docker-compose"
                docker compose logs
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
