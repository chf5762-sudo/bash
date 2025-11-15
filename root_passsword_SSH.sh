#!/bin/bash
#================================================================
# VPS Root SSH 登录终极解决脚本
# 警告：此脚本会暴力修改系统配置，可能导致系统不稳定
# 用途：彻底解决各种 VPS 无法用 root 密码登录的问题
#================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}======================================${NC}"
echo -e "${RED}  VPS Root SSH 终极解决方案${NC}"
echo -e "${RED}  警告：此脚本会暴力修改系统${NC}"
echo -e "${RED}======================================${NC}"
echo ""

# 检查是否为 root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误：必须以 root 身份运行此脚本${NC}"
   echo "请使用: sudo bash $0"
   exit 1
fi

echo -e "${YELLOW}[1/10] 检查并修复文件系统...${NC}"
# 重新挂载根分区为读写
mount -o remount,rw / 2>/dev/null || true
echo "✓ 文件系统检查完成"

echo -e "${YELLOW}[2/10] 设置 root 密码...${NC}"
# 固定密码
ROOT_PASS="@Cyn5762579"

# 方法1: 常规方式
echo "root:$ROOT_PASS" | chpasswd 2>/dev/null || {
    # 方法2: 使用 openssl 生成哈希
    HASH=$(openssl passwd -6 "$ROOT_PASS")
    sed -i "s|^root:[^:]*:|root:$HASH:|" /etc/shadow
}
echo "✓ root 密码已设置为: @Cyn5762579"

echo -e "${YELLOW}[3/10] 修复 shadow 和 passwd 文件权限...${NC}"
chmod 600 /etc/shadow
chmod 644 /etc/passwd
chmod 600 /etc/gshadow 2>/dev/null || true
chmod 644 /etc/group
echo "✓ 文件权限已修复"

echo -e "${YELLOW}[4/10] 备份原 SSH 配置...${NC}"
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)
echo "✓ 已备份到 /etc/ssh/sshd_config.bak.*"

echo -e "${YELLOW}[5/10] 暴力重写 SSH 配置...${NC}"
# 完全重写 sshd_config，移除所有限制
cat > /etc/ssh/sshd_config << 'EOF'
# VPS Root SSH 终极配置 - 完全开放版本
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# 认证设置 - 全部允许
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication yes
UsePAM yes

# 会话设置
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

# 安全设置（保持基本安全）
StrictModes no
MaxAuthTries 10
MaxSessions 10
LoginGraceTime 120

# 日志
SyslogFacility AUTH
LogLevel INFO
EOF

echo "✓ SSH 配置已重写"

echo -e "${YELLOW}[6/10] 禁用 GCP/AWS 特有的登录限制...${NC}"
# 禁用 Google OS Login
if command -v gcloud &> /dev/null; then
    gcloud compute instances remove-metadata $(hostname) --keys=enable-oslogin 2>/dev/null || true
    gcloud compute project-info remove-metadata --keys=enable-oslogin 2>/dev/null || true
fi

# 移除 Google/AWS 的 PAM 模块
sed -i 's/^auth.*pam_google/#&/' /etc/pam.d/sshd 2>/dev/null || true
sed -i 's/^auth.*pam_oslogin/#&/' /etc/pam.d/sshd 2>/dev/null || true
sed -i 's/^account.*pam_oslogin/#&/' /etc/pam.d/sshd 2>/dev/null || true

# 禁用 cloud-init 的 SSH 控制
if [ -d /etc/cloud/cloud.cfg.d/ ]; then
    cat > /etc/cloud/cloud.cfg.d/99-disable-ssh-control.cfg << 'EOF'
ssh_pwauth: true
disable_root: false
EOF
fi

echo "✓ 云平台限制已禁用"

echo -e "${YELLOW}[7/10] 禁用 SELinux (如果存在)...${NC}"
if command -v setenforce &> /dev/null; then
    setenforce 0 2>/dev/null || true
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config 2>/dev/null || true
    echo "✓ SELinux 已禁用"
else
    echo "✓ 系统无 SELinux"
fi

echo -e "${YELLOW}[8/10] 修复 PAM 配置...${NC}"
# 确保 PAM 允许密码认证
if [ -f /etc/pam.d/common-password ]; then
    sed -i 's/pam_unix.so.*/pam_unix.so obscure sha512/' /etc/pam.d/common-password
fi

if [ -f /etc/pam.d/system-auth ]; then
    sed -i 's/pam_unix.so.*/pam_unix.so sha512 shadow/' /etc/pam.d/system-auth
fi

echo "✓ PAM 配置已修复"

echo -e "${YELLOW}[9/10] 重启 SSH 服务...${NC}"
# 测试配置
sshd -t 2>&1 && {
    # 多种方式重启 SSH
    systemctl restart sshd 2>/dev/null || \
    systemctl restart ssh 2>/dev/null || \
    service sshd restart 2>/dev/null || \
    service ssh restart 2>/dev/null || \
    /etc/init.d/sshd restart 2>/dev/null || \
    /etc/init.d/ssh restart 2>/dev/null
    
    echo "✓ SSH 服务已重启"
} || {
    echo -e "${RED}SSH 配置测试失败，但继续执行...${NC}"
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
}

echo -e "${YELLOW}[10/10] 检查防火墙和端口...${NC}"
# 确保 SSH 端口开放
if command -v ufw &> /dev/null; then
    ufw allow 22/tcp 2>/dev/null || true
fi

if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-service=ssh 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
fi

# 检查端口监听
netstat -tlnp | grep :22 || ss -tlnp | grep :22
echo "✓ 端口检查完成"

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}  配置完成！${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo -e "${GREEN}root 用户名: root${NC}"
echo -e "${GREEN}root 密码: @Cyn5762579${NC}"
echo -e "${GREEN}SSH 配置已完全开放${NC}"
echo -e "${GREEN}所有云平台限制已禁用${NC}"
echo ""
echo -e "${YELLOW}请执行以下检查：${NC}"
echo "1. 查看 SSH 状态: systemctl status sshd"
echo "2. 查看 SSH 端口: netstat -tlnp | grep :22"
echo "3. 查看配置: cat /etc/ssh/sshd_config | grep -E 'PermitRootLogin|PasswordAuthentication'"
echo ""
echo -e "${YELLOW}现在可以尝试使用 SSH 客户端登录：${NC}"
echo "ssh root@$(hostname -I | awk '{print $1}')"
echo ""
echo -e "${RED}警告：此配置完全开放，仅用于临时调试${NC}"
echo -e "${RED}建议后续加固安全配置或使用密钥登录${NC}"
echo ""
echo -e "${GREEN}如果还有问题，查看日志：${NC}"
echo "tail -f /var/log/auth.log    # Ubuntu/Debian"
echo "tail -f /var/log/secure      # CentOS/RHEL"