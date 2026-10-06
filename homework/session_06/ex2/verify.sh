#!/usr/bin/env bash
# Chỉ kiểm tra, không thay đổi gì
id deployer
sudo grep -n '^%devops-admin' /etc/sudoers
echo '--- sudo -l (deployer) ---'
sudo -u deployer -H sudo -n -l
echo '--- restart cron ---'
sudo -u deployer -H sudo -n systemctl restart cron && echo "OK, khong hoi mat khau"
