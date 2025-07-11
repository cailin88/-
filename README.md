#!/system/bin/sh

MODDIR=${0%/*}
CONFIG="/data/adb/system_protector/config"
LOG_FILE="/data/adb/system_protector/protector.log"
NOTIFY="/data/adb/modules/system_protector/ksu_notify"
BACKUP_DIR="/data/adb/system_protector/backups"
LOCK_FILE="/data/adb/system_protector/locks/boot_backup.lock"

# 加载配置
[ -f "$CONFIG" ] && . "$CONFIG"

# 日志函数
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 精简系统备份函数
backup_system() {
  # 发送强通知
  $NOTIFY "正在备份中！请勿打开任何应用！！！"
  
  log "===== 开始系统备份 ====="
  
  local timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_path="$BACKUP_DIR/system_backup_$timestamp"
  
  mkdir -p "$backup_path"
  
  # 只备份/system目录 (精简备份)
  log "备份/system目录..."
  rsync -a --exclude='*/cache/*' --exclude='*/temp/*' /system/ "$backup_path/system"
  
  # 记录系统信息
  log "记录系统信息..."
  uname -a > "$backup_path/system_info.txt"
  getprop > "$backup_path/system_props.txt"
  
  # 创建MD5校验文件
  log "创建校验文件..."
  find "$backup_path" -type f -exec md5sum {} \; > "$backup_path/checksums.md5"
  
  # 压缩备份
  log "压缩备份..."
  tar -czf "$backup_path.tgz" -C "$backup_path" .
  rm -rf "$backup_path"
  
  # 保留最新3个备份
  ls -t "$BACKUP_DIR"/*.tgz 2>/dev/null | tail -n +4 | xargs rm -f --
  
  log "备份完成: $backup_path.tgz"
  $NOTIFY "系统备份已完成"
}

# 启动时备份
boot_backup() {
  # 检查锁文件
  [ ! -f "$LOCK_FILE" ] && return
  
  # 延迟启动备份
  sleep ${BACKUP_DELAY:-30}
  
  # 执行备份
  backup_system
  
  # 清除锁文件
  rm -f "$LOCK_FILE"
}

# 定时备份
periodic_backup() {
  while true; do
    # 等待10分钟
    sleep 600
    
    # 执行备份
    backup_system
  done
}

# 主服务
main_service() {
  log "===== 系统保护服务启动 ====="
  log "备份模式: $BACKUP_MODE"
  
  case "$BACKUP_MODE" in
    boot)
      boot_backup
      ;;
    periodic)
      periodic_backup
      ;;
    *)
      log "未知备份模式: $BACKUP_MODE"
      ;;
  esac
}

main_service
