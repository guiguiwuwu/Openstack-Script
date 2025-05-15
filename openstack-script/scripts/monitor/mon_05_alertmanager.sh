# 加载配置文件
source config.ini

# 安装 Alertmanager
fn_install_alertmanager() {
  echo -e "${YELLOW}正在安装 Alertmanager...${RESET}"

  # 从 URL 中提取 Alertmanager 版本号
  ALERT_VERSION=$(echo "$ALERTMANAGER_URL" | grep -oP 'v\K[0-9.]+')

  if [ -z "$ALERT_VERSION" ]; then
    echo -e "${RED}无法从 URL 中提取版本号，请检查 URL 配置${RESET}"
    exit 1
  fi

  echo -e "${YELLOW}检测到 Alertmanager 版本: ${ALERT_VERSION}${RESET}"

  # 下载 Alertmanager 压缩包
  wget $ALERTMANAGER_URL -O alertmanager.tar.gz

  # 解压文件
  tar -xzf alertmanager.tar.gz
  sudo mv alertmanager-${ALERT_VERSION}.linux-amd64 /usr/local/alertmanager

  # 创建必要的目录
  sudo mkdir -p /etc/alertmanager /var/lib/alertmanager
  sudo mv /usr/local/alertmanager/alertmanager.yml /etc/alertmanager/

  # 清理下载的压缩包
  rm alertmanager.tar.gz

  echo -e "${GREEN}Alertmanager 安装完成${RESET}"
}

# 配置 Alertmanager
fn_configure_alertmanager() {
  echo -e "${YELLOW}正在配置 Alertmanager...${RESET}"

  # 生成 Alertmanager 配置文件
  sudo tee /etc/alertmanager/alertmanager.yml > /dev/null <<EOF
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.qq.com:465'
  smtp_require_tls: false
  smtp_from: '1811657187@qq.com'
  smtp_auth_username: '1811657187@qq.com'
  smtp_auth_password: 'ipopbjrfrcbndche'
route:
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 3h
  receiver: 'email'
receivers:
  - name: 'email'
    email_configs:
      - to: '1811657187@qq.com'
        send_resolved: true
EOF
  echo -e "${GREEN}Alertmanager 配置文件已创建: /etc/alertmanager/alertmanager.yml${RESET}"
}

# 启动 Alertmanager 服务
fn_start_alertmanager() {
  echo -e "${YELLOW}正在启动 Alertmanager...${RESET}"

  # 创建 systemd 服务文件
  sudo tee /etc/systemd/system/alertmanager.service > /dev/null <<EOF
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/alertmanager/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager \
  --web.listen-address=:9093
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  # 重载 systemd 并启动服务
  sudo systemctl daemon-reload
  sudo systemctl enable alertmanager
  sudo systemctl start alertmanager

  echo -e "${GREEN}Alertmanager 服务启动成功${RESET}"
}

# 检查 Alertmanager 服务状态
fn_check_alertmanager_status() {
  echo -e "${YELLOW}正在检查 Alertmanager 服务状态...${RESET}"

  if systemctl is-active --quiet alertmanager; then
    echo -e "${GREEN}Alertmanager 服务正在运行${RESET}"
  else
    echo -e "${RED}Alertmanager 服务未运行，请检查服务状态${RESET}"
  fi
}

# 执行主要功能
fn_install_alertmanager
fn_configure_alertmanager
fn_start_alertmanager
fn_check_alertmanager_status