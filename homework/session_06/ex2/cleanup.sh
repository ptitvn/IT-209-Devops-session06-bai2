#!/usr/bin/env bash
# Gỡ toàn bộ cấu hình bài 2 để làm lại từ đầu
read -rp "Xóa user deployer, nhóm devops-admin và quy tắc sudoers? (y/N) " a
[ "$a" = "y" ] || exit 0
sudo cp -p /etc/sudoers /tmp/sudoers.clean
sudo sed -i '/^# Bai 2 session 06/d;/^%devops-admin /d' /tmp/sudoers.clean
sudo visudo -cf /tmp/sudoers.clean && sudo install -m 0440 -o root -g root /tmp/sudoers.clean /etc/sudoers
sudo userdel -r deployer 2>/dev/null
sudo groupdel devops-admin 2>/dev/null
echo "Đã dọn xong."
