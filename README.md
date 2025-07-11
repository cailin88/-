增强版系统保护模块：刷入时选择 + 精简备份
 
以下是完整的模块实现，包含刷入时的音量键选择功能和只备份 /system 目录的精简方案：
 
# 模块目录结构
SystemProtector/
├── META-INF/
│   └── com/
│       └── google/
│           └── android/
│               ├── update-binary
│               └── updater-script
├── module.prop
├── post-fs-data.sh
├── service.sh
├── common/
│   └── system_protector.sh
└── system/
    └── bin/
        ├── ksu_notify
        └── keycheck # 按键检测工具
 
 
1. 模块配置文件 ( module.prop )
 
id=system_protector
name=系统保护守护程序
version=v1.4
versionCode=5
author=@好无聊—QQ=3488668121
description=刷入时选择模式+精简系统备份
support=暂时不提供下载地址
 
 
2. 按键检测工具 ( system/bin/keycheck )
 
#!/system/bin/sh

# 按键检测工具
event_input=$(getevent -qlc 1 | head -1 | awk '{print $3}')

if [ -z "$event_input" ]; then
  echo "error"
  exit 1
fi

# 监听按键
getevent -qlc 10 "$event_input" | while read -r line; do
  case "$line" in
    *KEY_VOLUMEUP*)
      echo "up"
      exit 0
      ;;
    *KEY_VOLUMEDOWN*)
      echo "down"
      exit 0
      ;;
  esac
done

echo "timeout"
 
 
3. 安装脚本 ( META-INF/com/google/android/update-binary )
 
#!/sbin/sh

OUTFD=$2
ZIPFILE=$3

ui_print() {
  echo -e "ui_print $1\nui_print" > /proc/self/fd/$OUTFD
}

show_menu() {
  ui_print " "
  ui_print "===== 请选择备份模式 ====="
  ui_print "音量+ ↑: 启动时备份"
  ui_print "音量- ↓: 10分钟自动备份"
  ui_print " "
  ui_print "请在5秒内选择..."
  ui_print "========================="
}

# 开始安装
ui_print "正在安装系统保护模块..."

# 显示菜单
show_menu

# 检测按键选择
choice=$($MODPATH/system/bin/keycheck)

case $choice in
  up)
    MODE="boot"
    ui_print "已选择: 启动时备份模式"
    ;;
  down)
    MODE="periodic"
    ui_print "已选择: 10分钟自动备份模式"
    ;;
  *)
    MODE="boot"
    ui_print "超时未选择，使用默认: 启动时备份"
    ;;
esac

# 创建配置目录
mkdir -p /data/adb/system_protector

# 保存模式选择
echo "BACKUP_MODE=$MODE" > /data/adb/system_protector/config
echo "BACKUP_DELAY=30" >> /data/adb/system_protector/config

# 继续安装
ui_print "- 解压文件..."
unzip -o "$ZIPFILE" -d $MODPATH >&2

# 设置权限
ui_print "- 设置权限..."
chmod 755 $MODPATH/post-fs-data.sh
chmod 755 $MODPATH/service.sh
chmod 755 $MODPATH/system/bin/ksu_notify
chmod 755 $MODPATH/system/bin/keycheck
chmod 755 $MODPATH/common/system_protector.sh

ui_print "安装完成!"
exit 0
 
 
4. 初始化脚本 ( post-fs-data.sh )
 
#!/system/bin/sh

MODDIR=${0%/*}

# 创建备份目录
mkdir -p /data/adb/system_protector/backups
mkdir -p /data/adb/system_protector/locks

# 安装通知工具
cp -f $MODDIR/system/bin/ksu_notify /data/adb/modules/system_protector/
chmod 755 /data/adb/modules/system_protector/ksu_notify

# 加载配置
CONFIG="/data/adb/system_protector/config"
[ -f "$CONFIG" ] && . "$CONFIG"

# 如果是启动模式，创建备份锁
if [ "$BACKUP_MODE" = "boot" ]; then
  touch /data/adb/system_protector/locks/boot_backup.lock
fi
 
 
5. 主服务脚本 ( service.sh )
 
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
 
 
6. 通知工具 ( system/bin/ksu_notify )
 
#!/system/bin/sh

# 强通知工具
MESSAGE="$1"

# 发送高优先级通知
su -c "am broadcast -a com.kerneksu.NOTIFY \
  --es \"title\" \"系统保护\" \
  --es \"message\" \"$MESSAGE\" \
  --es \"priority\" \"max\" \
  --es \"package\" \"com.android.shell\" \
  --es \"sticky\" \"true\" >/dev/null 2>&1"

# 发送Toast通知
su -c "am service call notification 1 s16 \"com.android.shell\" i32 0 s16 \"系统保护\" s16 \"$MESSAGE\" i32 1 >/dev/null 2>&1"

# 写入系统日志
log -p i -t "SystemProtector" "NOTIFICATION: $MESSAGE"
 
 
7. 管理脚本 ( common/system_protector.sh )
 
#!/system/bin/sh

MODDIR=${0%/*}
NOTIFY="/data/adb/modules/system_protector/ksu_notify"
CONFIG="/data/adb/system_protector/config"
BACKUP_DIR="/data/adb/system_protector/backups"

# 加载配置
[ -f "$CONFIG" ] && . "$CONFIG"

# 切换备份模式
switch_mode() {
  if [ "$BACKUP_MODE" = "boot" ]; then
    new_mode="periodic"
  else
    new_mode="boot"
  fi
  
  sed -i "s/BACKUP_MODE=.*/BACKUP_MODE=$new_mode/" "$CONFIG"
  
  # 重启服务
  pkill -f "service.sh"
  nohup "$MODDIR/service.sh" >/dev/null 2>&1 &
  
  $NOTIFY "已切换到${new_mode}备份模式"
  echo "✅ 备份模式已切换为: $new_mode"
}

# 手动备份
manual_backup() {
  $NOTIFY "正在启动手动系统备份..."
  
  # 调用备份函数
  "$MODDIR/service.sh" backup_system
  
  $NOTIFY "手动备份已完成"
}

# 查看备份
list_backups() {
  echo -e "\n系统备份列表:"
  ls -lt "$BACKUP_DIR"/*.tgz 2>/dev/null || echo "暂无备份"
  
  read -p "输入回车返回主菜单..."
}

# 主菜单
show_menu() {
  while true; do
    echo -e "\n===== 系统保护管理菜单 ====="
    echo "当前模式: $BACKUP_MODE"
    echo "1. 切换备份模式"
    echo "2. 立即备份系统"
    echo "3. 查看备份列表"
    echo "4. 设置备份延迟"
    echo "5. 退出"
    echo "============================"
    read -p "请选择操作 [1-5]: " choice
    
    case $choice in
      1) switch_mode ;;
      2) manual_backup ;;
      3) list_backups ;;
      4)
        current_delay=${BACKUP_DELAY:-30}
        echo "当前备份延迟: ${current_delay}秒"
        read -p "请输入新延迟(秒): " new_delay
        
        if [[ "$new_delay" =~ ^[0-9]+$ ]] && [ "$new_delay" -ge 5 ]; then
          sed -i "s/BACKUP_DELAY=.*/BACKUP_DELAY=$new_delay/" "$CONFIG"
          $NOTIFY "启动延迟设置为${new_delay}秒"
          echo "✅ 启动延迟已设置为: ${new_delay}秒"
        else
          echo "错误: 请输入大于5的整数"
        fi
        ;;
      5) exit 0 ;;
      *) echo "无效选择" ;;
    esac
  done
}

show_menu
 
 
刷入时选择功能说明
 
刷入过程交互：
 
正在安装系统保护模块...

===== 请选择备份模式 =====
音量+ ↑: 启动时备份
音量- ↓: 10分钟自动备份

请在5秒内选择...
========================
