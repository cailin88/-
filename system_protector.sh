#!/system/bin/sh

MODDIR=${0%/*}
CONFIG_FILE="/data/adb/universal_protector/config"
LOG_FILE="/data/adb/universal_protector/protector.log"

# 加载配置
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# 通用通知函数
notify() {
  $NOTIFY_BIN "$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# 切换备份模式
switch_mode() {
  if [ "$BACKUP_MODE" = "boot" ]; then
    new_mode="periodic"
  else
    new_mode="boot"
  fi
  
  sed -i "s/BACKUP_MODE=.*/BACKUP_MODE=$new_mode/" "$CONFIG_FILE"
  
  # 重启服务
  pkill -f "service.sh"
  nohup "$MODDIR/service.sh" >/dev/null 2>&1 &
  
  notify "已切换到${new_mode}备份模式"
  echo "✅ 备份模式已切换为: $new_mode"
}

# 手动备份
manual_backup() {
  notify "正在启动手动系统备份..."
  
  # 创建锁文件触发启动备份
  touch "/data/adb/universal_protector/locks/boot_backup.lock"
  
  # 执行备份
  "$MODDIR/service.sh" &
  backup_pid=$!
  
  notify "正在安全备份中..."
  wait $backup_pid
  notify "手动备份安全完成"
}

# 完全卸载
uninstall_module() {
  echo "正在准备卸载模块..."
  notify "正在卸载系统保护模块..."
  
  # 执行卸载脚本
  sh "$MODDIR/uninstall.sh"
  
  exit 0
}

# 主菜单
show_menu() {
  while true; do
    echo -e "\n===== 通用系统保护管理菜单 ====="
    echo "当前模式: $BACKUP_MODE"
    echo "1. 切换备份模式"
    echo "2. 立即备份系统"
    echo "3. 查看备份列表"
    echo "4. 设置备份延迟"
    echo "5. 完全卸载模块"
    echo "6. 退出"
    echo "==============================="
    read -p "请选择操作 [1-6]: " choice
    
    case $choice in
      1) switch_mode ;;
      2) manual_backup ;;
      3) 
        echo -e "\n备份列表:"
        ls -lt "/data/adb/universal_protector/backups"
        read -p "按回车继续..."
        ;;
      4)
        current_delay=${BACKUP_DELAY:-30}
        echo "当前备份延迟: ${current_delay}秒"
        read -p "请输入新延迟(秒): " new_delay
        
        if [[ "$new_delay" =~ ^[0-9]+$ ]] && [ "$new_delay" -ge 5 ]; then
          sed -i "s/BACKUP_DELAY=.*/BACKUP_DELAY=$new_delay/" "$CONFIG_FILE"
          notify "启动延迟设置为${new_delay}秒"
          echo "✅ 启动延迟已设置为: ${new_delay}秒"
        else
          echo "错误: 请输入大于5的整数"
        fi
        ;;
      5) uninstall_module ;;
      6) exit 0 ;;
      *) echo "无效选择" ;;
    esac
  done
}

show_menu