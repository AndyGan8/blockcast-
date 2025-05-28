#!/bin/bash

# 脚本名称：deploy_blockcast_node.sh

# 设置错误处理：任何命令失败则退出
set -e

# 定义目录
BLOCKCAST_DIR="beacon-docker-compose"

# 打印信息函数
print_info() {
  echo -e "\033[1;34m$1\033[0m"
}

# 安装并启动节点函数
install_and_start_node() {
  print_info "开始部署Blockcast节点..."

  # 1. 启动Docker服务
  print_info "启动Docker服务..."
  sudo systemctl start docker
  print_info "Docker服务已启动"

  # 2. 克隆代码库
  print_info "克隆代码库..."
  if [ -d "$BLOCKCAST_DIR" ]; then
    print_info "目录 $BLOCKCAST_DIR 已存在，跳过克隆"
  else
    git clone https://github.com/Blockcast/beacon-docker-compose.git
  fi

  # 3. 进入目录
  print_info "进入 $BLOCKCAST_DIR 目录..."
  cd "$BLOCKCAST_DIR"

  # 4. 安装并运行节点
  print_info "启动节点..."
  docker compose up -d
  print_info "节点已启动"
}

# 获取设备信息函数
get_device_info() {
  if [ -d "$BLOCKCAST_DIR" ] && [ -f "$BLOCKCAST_DIR/docker-compose.yml" ]; then
    print_info "获取设备信息..."
    print_info "正在执行 blockcastd init..."
    cd "$BLOCKCAST_DIR"
    docker compose exec -T blockcastd blockcastd init > device_info.txt
    print_info "设备信息已保存到 $BLOCKCAST_DIR/device_info.txt"
    print_info "请保存 Hardware ID 和 Challenge Key 用于节点注册。"
    cd - >/dev/null
  else
    print_info "错误：未找到 $BLOCKCAST_DIR/docker-compose.yml 文件，请先安装并启动节点。"
  fi
  echo "按任意键返回主菜单..."
  read -n 1
}

# 查看节点日志函数
view_node_logs() {
  if [ -d "$BLOCKCAST_DIR" ] && [ -f "$BLOCKCAST_DIR/docker-compose.yml" ]; then
    print_info "查看节点日志..."
    cd "$BLOCKCAST_DIR"
    docker logs -f blockcastd
    cd - >/dev/null
  else
    print_info "错误：未找到 $BLOCKCAST_DIR/docker-compose.yml 文件，请先安装并启动节点。"
  fi
  echo "按任意键返回主菜单..."
  read -n 1
}

# 主菜单函数
main_menu() {
  while true; do
    clear
    print_info "Blockcast 节点管理脚本"
    echo "1. 安装并启动节点"
    echo "2. 查看节点日志"
    echo "3. 获取设备信息"
    echo "4. 退出"
    read -p "请输入选项 (1-4): " choice

    case $choice in
      1)
        install_and_start_node
        echo "按任意键返回主菜单..."
        read -n 1
        cd - >/dev/null 2>/dev/null || true # 返回原目录，忽略错误
        ;;
      2)
        view_node_logs
        ;;
      3)
        get_device_info
        ;;
      4)
        print_info "退出脚本..."
        exit 0
        ;;
      *)
        print_info "无效选项，请输入 1-4。"
        echo "按任意键返回主菜单..."
        read -n 1
        ;;
    esac
  done
}

# 检查依赖
command -v docker >/dev/null 2>&1 || { print_info "错误：Docker 未安装，请先安装 Docker。"; exit 1; }
command -v git >/dev/null 2>&1 || { print_info "错误：Git 未安装，请先安装 Git。"; exit 1; }

# 执行主菜单
main_menu
