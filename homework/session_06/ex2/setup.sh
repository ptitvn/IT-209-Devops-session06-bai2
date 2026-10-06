#!/usr/bin/env bash
# Bài 2: Cấu hình phân quyền nhóm và sudoers bằng visudo
# Chạy:  bash setup.sh      (user thường, script tự gọi sudo khi cần)
set -uo pipefail

GROUP="devops-admin"
USER_NAME="deployer"
OWNER="${SUDO_USER:-$USER}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUDO=""; [ "$EUID" -ne 0 ] && SUDO="sudo"
PRETTY="$( . /etc/os-release && echo "$PRETTY_NAME" )"
SYSTEMCTL="/usr/bin/systemctl"
RULE="%$GROUP ALL=(ALL) NOPASSWD: $SYSTEMCTL start *, $SYSTEMCTL stop *, $SYSTEMCTL restart *, $SYSTEMCTL status *"

if [ "$OWNER" = "root" ]; then
  echo "Lỗi: hãy chạy bằng tài khoản non-root có sudo."; exit 1
fi
[ -x "$SYSTEMCTL" ] || { echo "Không thấy $SYSTEMCTL. Hệ thống chưa có systemd?"; exit 1; }

LOG=""
log() { LOG+="$*"$'\n'; echo "\$ $*"; }
run() { log "$*"; eval "$SUDO $*"; }

# --- Kiểm tra systemd (WSL cần bật) ---
HAS_SYSTEMD=1
if [ ! -d /run/systemd/system ]; then
  HAS_SYSTEMD=0
  cat <<MSG
[CẢNH BÁO] systemd chưa chạy trong hệ thống này (thường gặp trên WSL cũ).
Script vẫn cấu hình user/group/sudoers, nhưng không thể restart cron.
Để bật systemd trên WSL, chạy:
  printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf
rồi trong PowerShell: wsl --shutdown, mở lại Ubuntu và chạy lại bash setup.sh
MSG
fi

echo "== Bước 1: đảm bảo có dịch vụ cron =="
if ! command -v cron >/dev/null 2>&1 && [ ! -x /usr/sbin/cron ]; then
  run apt-get update -qq
  run apt-get install -y -qq cron
fi
[ "$HAS_SYSTEMD" = 1 ] && run systemctl enable --now cron

echo "== Bước 2: tạo nhóm và user =="
if getent group "$GROUP" >/dev/null; then echo "(nhóm $GROUP đã tồn tại)"; else run groupadd "$GROUP"; fi
if id "$USER_NAME" >/dev/null 2>&1; then echo "(user $USER_NAME đã tồn tại)"; else
  run adduser --disabled-password --gecos '""' "$USER_NAME"
fi
run usermod -aG "$GROUP" "$USER_NAME"

echo "== Bước 3: thêm quy tắc vào /etc/sudoers (kiểm tra cú pháp bằng visudo -c) =="
if $SUDO grep -qF "%$GROUP " /etc/sudoers; then
  echo "(quy tắc cho %$GROUP đã có, bỏ qua)"
else
  TMP="$(mktemp)"
  log "sudo cp -p /etc/sudoers /etc/sudoers.bak.ex2     # sao lưu"
  $SUDO cp -p /etc/sudoers /etc/sudoers.bak.ex2
  $SUDO cat /etc/sudoers > "$TMP"
  { echo; echo "# Bai 2 session 06: nhom $GROUP duoc quan ly dich vu, khong can mat khau"; echo "$RULE"; } >> "$TMP"
  log "sudo visudo -cf <file-tam>                       # kiem tra cu phap truoc khi ap dung"
  if $SUDO visudo -cf "$TMP"; then
    log "sudo install -m 0440 -o root -g root <file-tam> /etc/sudoers"
    $SUDO install -m 0440 -o root -g root "$TMP" /etc/sudoers
  else
    echo "Cú pháp sai, KHÔNG ghi vào /etc/sudoers."; rm -f "$TMP"; exit 1
  fi
  rm -f "$TMP"
fi
log "sudo visudo -c"
$SUDO visudo -c

echo
echo "== Bước 4: kiểm tra với tài khoản $USER_NAME =="
as_dep() { $SUDO -u "$USER_NAME" -H bash -c "$1" 2>&1; }

ID_OUT="$(id "$USER_NAME")"
RULE_OUT="$($SUDO grep -n "^%$GROUP" /etc/sudoers)"
SUDOL_OUT="$(as_dep 'sudo -n -l')"; SUDOL_RC=$?
echo "\$ id $USER_NAME";           echo "$ID_OUT"
echo "\$ sudo -l  (với user $USER_NAME)"; echo "$SUDOL_OUT"

if [ "$HAS_SYSTEMD" = 1 ]; then
  RESTART_OUT="$(as_dep 'sudo -n systemctl restart cron && echo "-> restart cron THANH CONG, khong hoi mat khau"')"
  STATUS_OUT="$(as_dep 'sudo -n systemctl status cron --no-pager | head -n 5')"
else
  RESTART_OUT="(bỏ qua: systemd chưa chạy)"; STATUS_OUT="(bỏ qua: systemd chưa chạy)"
fi
DENY_OUT="$(as_dep 'sudo -n cat /etc/shadow >/dev/null && echo BAD-DUOC-PHEP')"
echo "\$ sudo systemctl restart cron  (với user $USER_NAME)"; echo "$RESTART_OUT"
echo "\$ sudo cat /etc/shadow  (phải bị từ chối)"; echo "$DENY_OUT"

PASS=1
echo "$SUDOL_OUT" | grep -q "NOPASSWD" || PASS=0
echo "$SUDOL_OUT" | grep -q "systemctl" || PASS=0
id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx "$GROUP" || PASS=0
echo "$DENY_OUT" | grep -q "BAD-DUOC-PHEP" && PASS=0
if [ "$HAS_SYSTEMD" = 1 ]; then echo "$RESTART_OUT" | grep -q "THANH CONG" || PASS=0; fi
if [ "$PASS" = 1 ]; then
  RESULT="ĐẠT"; [ "$HAS_SYSTEMD" = 0 ] && RESULT="ĐẠT PHẦN CẤU HÌNH (chưa test restart vì thiếu systemd)"
else RESULT="CHƯA ĐẠT - xem lại output"; fi
echo; echo "Kết quả: $RESULT"

# ---- Sinh README.md ----
cat > "$DIR/README.md" <<README
# Bài 2: Cấu hình phân quyền Nhóm và sudoers bằng visudo

- Ngày thực hiện: $(date '+%Y-%m-%d %H:%M')
- Máy: $(hostname) - $PRETTY
- Tài khoản quản trị dùng để cấu hình: \`$OWNER\`

## 1. Mục tiêu

Cho nhóm \`$GROUP\` (có user \`$USER_NAME\`) quyền \`start/stop/restart/status\` dịch vụ qua \`systemctl\` **không cần mật khẩu**, nhưng **không** cấp toàn quyền root.

## 2. Nhật ký lệnh đã thực hiện

\`\`\`bash
$LOG\`\`\`

## 3. Dòng cấu hình đã thêm vào /etc/sudoers

\`\`\`
$RULE_OUT
\`\`\`

Giải thích: \`%$GROUP\` (dấu \`%\` = nhóm) \`ALL=(ALL)\` (mọi host, chạy với tư cách mọi user) \`NOPASSWD:\` (không hỏi mật khẩu) chỉ với các lệnh \`systemctl start|stop|restart|status\` có đường dẫn đầy đủ.

Quy tắc được kiểm tra bằng \`visudo -c\` trước khi áp dụng, tránh viết sai cú pháp làm mất quyền sudo của toàn hệ thống.

## 4. Kết quả kiểm tra

Thông tin user:
\`\`\`
\$ id $USER_NAME
$ID_OUT
\`\`\`

Kết quả \`sudo -l\` khi đăng nhập bằng \`$USER_NAME\`:
\`\`\`
\$ sudo -l
$SUDOL_OUT
\`\`\`

Restart dịch vụ cron (không hỏi mật khẩu; dùng \`sudo -n\` để chứng minh không có prompt):
\`\`\`
\$ sudo systemctl restart cron
$RESTART_OUT
\`\`\`

Trạng thái cron:
\`\`\`
\$ sudo systemctl status cron
$STATUS_OUT
\`\`\`

Kiểm tra nguyên tắc đặc quyền tối thiểu: \`$USER_NAME\` **không** được chạy lệnh khác:
\`\`\`
\$ sudo cat /etc/shadow
$DENY_OUT
\`\`\`

**Kết luận:** $RESULT

## 5. Lưu ý bảo mật

- Ký tự \`*\` trong sudoers khớp mọi tham số, nên \`systemctl restart *\` cũng khớp cả cú pháp có thêm tùy chọn. Môi trường thật nên liệt kê rõ dịch vụ cần cấp (ví dụ \`systemctl restart nginx\`).
- Luôn sửa sudoers bằng \`visudo\` (hoặc kiểm tra bằng \`visudo -cf\`) để tránh lỗi cú pháp khóa mất sudo.
README

echo; echo "Đã tạo $DIR/README.md với output thực tế."
