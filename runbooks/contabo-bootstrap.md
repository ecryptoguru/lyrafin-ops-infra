# Contabo Bootstrap Runbook

## VPS Provisioning

### 1. Provision VPS

- **Provider:** Contabo Cloud VPS 10
- **Specs:** 4 vCPU, 8 GB RAM, 150 GB SSD (16 GB RAM preferred if budget allows)
- **OS:** Ubuntu 24.04 LTS

### 2. Initial SSH Access

```bash
ssh root@<vps-ip>
```

### 3. Create deploy user

```bash
adduser deploy
usermod -aG sudo deploy
mkdir -p /home/deploy/.ssh
cp ~/.ssh/authorized_keys /home/deploy/.ssh/
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
```

### 4. Harden SSH

Edit `/etc/ssh/sshd_config`:

```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers deploy
```

```bash
systemctl restart sshd
```

### 5. Configure Firewall (UFW)

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

### 6. Install Fail2ban

```bash
apt update
apt install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban
```

### 7. Enable Unattended Upgrades

```bash
apt install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
```

### 8. Install Docker Engine

```bash
apt install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker deploy
```

### 9. Configure Docker Log Rotation

Create `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  }
}
```

```bash
systemctl restart docker
```

### 10. Install Doppler CLI

```bash
curl -Ls https://cli.doppler.com/install.sh | sh
doppler login
doppler setup
# Configure project: lyrafin-ops, environment: production
```

### 11. Clone the Ops Repo

```bash
su - deploy
git clone <your-repo-url> ~/lyrafin-ops-infra
cd ~/lyrafin-ops-infra
doppler setup
```

### 12. Deploy Services

```bash
# Start all services with production secrets
# Using -f flags explicitly to avoid auto-merging docker-compose.override.yml (local dev only)
doppler run -- ./scripts/preflight-prod.sh
doppler run -- docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile all --profile production up -d

# Verify
docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile all --profile production ps
```

### 13. Verify Caddy TLS

```bash
# Check Caddy logs for certificate issuance
docker logs caddy | grep "certificate"

# Test endpoints
curl -I https://newsletter.lyrafinai.com
curl -I https://social.lyrafinai.com
curl https://convert.lyrafinai.com/health
```

## Post-Bootstrap Checklist

- [ ] SSH key login only (no password)
- [ ] UFW active (22, 80, 443 only)
- [ ] Fail2ban running
- [ ] Docker installed and log rotation configured
- [ ] Doppler CLI installed and configured
- [ ] All containers healthy
- [ ] Caddy certificates issued
- [ ] DNS resolves for all three subdomains
- [ ] Store SSH details in password manager (1Password/Bitwarden)
