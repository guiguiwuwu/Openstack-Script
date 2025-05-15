#!/bin/bash
#加载配置文件 config.ini
source config.ini

#安装prometheus
install_prometheus() {
    echo -e "${YELLOW}Installing Prometheus...${RESET}"

    # 通过环境变量获取 Prometheus 的版本号
    PROM_VERSION=$(echo "$PROMETHEUS_URL" | grep -oP 'v\K[0-9.]+')

    if [ -z "$PROM_VERSION" ]; then
        echo -e "${RED}Failed to extract Prometheus version from URL. Please check the URL.${RESET}"
        exit 1
    fi

    echo -e "${YELLOW}Detected Prometheus version: ${PROM_VERSION}${RESET}"

    # 下载 Prometheus tarball
    wget $PROMETHEUS_URL -O prometheus.tar.gz

    # 解压文件
    tar -xzf prometheus.tar.gz
    sudo mv prometheus-${PROM_VERSION}.linux-amd64 /usr/local/prometheus

    # 创建必要的目录
    sudo mkdir -p /etc/prometheus /var/lib/prometheus
    sudo mv /usr/local/prometheus/prometheus.yml /etc/prometheus/

    # 清理下载的压缩包
    rm prometheus.tar.gz

    echo -e "${GREEN}Prometheus installed successfully.${RESET}"
}

# 配置 Prometheus
configure_prometheus() {
    echo -e "${YELLOW}Configuring Prometheus...${RESET}"

    # 生成 Prometheus 配置文件
    sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['10.0.0.10:9093']   # Alertmanager 地址，端口保持默认
rule_files:
  - "rules/*.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['10.0.0.10:9090']

  - job_name: 'openstack-exporter'
    static_configs:
      - targets: ['10.0.0.10:9180']

  - job_name: 'openstack_python'
    static_configs:
      - targets: ['10.0.0.10:9184']

  - job_name: 'openstack_node'
    static_configs:
      - targets: ["${CTL_MANAGEMENT}:9100", "${COM_MANAGEMENT}:9100", "${BLK_MANAGEMENT}:9100"]

EOF
    # 创建规则目录
    sudo mkdir -p /etc/prometheus/rules
    # 创建规则文件
    sudo tee /etc/prometheus/rules/openstack_alerts.yml > /dev/null <<EOF
# /etc/prometheus/rules/openstack_alerts.yml
groups:
- name: openstack.component.rules      # 文件内唯一的 rule group 名
  interval: 30s                       # 每 30 s 评估一次（可按需调整）
  rules:

  # --- 服务级 up 指标 ------------------------------------------------------
  - alert: NovaServiceDown
    expr: openstack_nova_up == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Nova API 服务宕机"
      description: "openstack_nova_up 为 0 已超过 2 分钟，Nova API 无响应。"

  - alert: NeutronServiceDown
    expr: openstack_neutron_up == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Neutron 服务宕机"
      description: "openstack_neutron_up 为 0 已超过 2 分钟，网络服务不可用。"

  - alert: CinderServiceDown
    expr: openstack_cinder_up == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Cinder 服务宕机"
      description: "openstack_cinder_up 为 0 已超过 2 分钟，块存储服务不可用。"

  - alert: GlanceServiceDown
    expr: openstack_glance_up == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Glance 服务宕机"
      description: "openstack_glance_up 为 0 已超过 2 分钟，镜像服务不可用。"

  - alert: KeystoneServiceDown
    expr: openstack_identity_up == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Keystone 身份服务宕机"
      description: "openstack_identity_up 为 0 已超过 2 分钟，认证鉴权失效。"

  - alert: PlacementServiceDown
    expr: openstack_placement_up == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Placement 服务宕机"
      description: "openstack_placement_up 为 0 已超过 2 分钟，资源调度失效。"

  # --- Agent 级状态指标 ----------------------------------------------------
  - alert: NovaComputeAgentDown
    expr: openstack_nova_agent_state{service="nova-compute"} != 1
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "nova-compute Agent 宕机 ({{ $labels.hostname }})"
      description: "Nova 计算节点 {{ $labels.hostname }} 已离线 2 分钟以上。"

  - alert: NeutronAgentDown
    expr: openstack_neutron_agent_state != 1
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Neutron {{ $labels.service }} Agent 宕机 ({{ $labels.hostname }})"
      description: "Neutron Agent {{ $labels.service }} 在主机 {{ $labels.hostname }} 已离线 2 分钟以上。"

  - alert: CinderVolumeAgentDown
    expr: openstack_cinder_agent_state{service="cinder-volume"} != 1
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Cinder Volume Agent 宕机 ({{ $labels.hostname }})"
      description: "Cinder Volume Agent 主机 {{ $labels.hostname }} 已离线 2 分钟以上。"


EOF
    # 创建规则目录
    sudo mkdir -p /etc/prometheus/rules
    # 创建规则文件
    sudo tee /etc/prometheus/rules/node_alerts.yml > /dev/null <<EOF
#/etc/prometheus/rules/node_alerts.yml
groups:
- name: node.rules
  rules:

  # 1) Node exporter down → 说明整台主机或 node_exporter 不可达
  - alert: NodeDown
    expr: up{job="openstack_node"} == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "节点离线 ({{ $labels.instance }})"
      description: "Prometheus 已连续 2 分钟无法抓取 {{ $labels.instance }} 的 Node Exporter。请检查主机或 node_exporter 服务。"

  # 2) CPU total usage > 90%
  - alert: NodeCPUHigh
    expr: |
      100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
        > 90
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "CPU 利用率过高 ({{ $labels.instance }})"
      description: "过去 5 分钟 {{ $labels.instance }} 的平均 CPU 使用率超过 90%（当前 {{ printf \"%.1f\" $value }}%）。"

  # 3) Memory usage > 90%
  - alert: NodeMemoryHigh
    expr: |
      (1 - node_memory_MemAvailable_bytes
             / node_memory_MemTotal_bytes) * 100
        > 90
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "内存使用率过高 ({{ $labels.instance }})"
      description: "过去 5 分钟 {{ $labels.instance }} 的内存使用率超过 90%（当前 {{ printf \"%.1f\" $value }}%）。"

  # 4) Filesystem usage > 90%  (排除临时文件系统)
  - alert: NodeFilesystemFull
    expr: |
      (1 - node_filesystem_free_bytes{fstype!~"tmpfs|overlay"}
             / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) * 100
        > 90
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "磁盘分区容量不足 ({{ $labels.instance }})"
      description: "{{ $labels.instance }} 的挂载点 {{ $labels.mountpoint }} 已使用 {{ printf \"%.1f\" $value }}%，超过 90%。请及时清理或扩容。"

EOF
    echo -e "${GREEN}Prometheus configuration file created at /etc/prometheus/prometheus.yml.${RESET}"
}

# 启动 Prometheus 服务
setup_systemd_service() {
    echo -e "${YELLOW}Setting up Prometheus as a systemd service...${RESET}"

    # 创建 systemd service file
    sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=root
ExecStart=/usr/local/prometheus/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # 重启 systemd，启用并启动服务
    sudo systemctl daemon-reload
    sudo systemctl enable prometheus
    sudo systemctl start prometheus

    # 验证服务状态
    if systemctl is-active --quiet prometheus; then
        echo -e "${GREEN}Prometheus service is running.${RESET}"
    else
        echo -e "${RED}Failed to start Prometheus service.${RESET}"
        exit 1
    fi
}

# 安装 Prometheus
install_prometheus
configure_prometheus
setup_systemd_service

echo -e "${GREEN}Prometheus installed, configured, and dynamic target updates scheduled successfully.${RESET}"


