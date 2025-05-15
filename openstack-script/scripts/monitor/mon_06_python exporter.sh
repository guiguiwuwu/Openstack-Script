# ① 安装必备包
sudo apt update
sudo apt install -y python3 python3-venv gcc libffi-dev pkg-config

# ② 为 Exporter 建目录
sudo mkdir -p /opt/py_os_exporter
sudo chown $USER /opt/py_os_exporter
cd /opt/py_os_exporter

# ③ 创建虚拟环境并安装库
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install openstacksdk prometheus-client

#准备认证文件
mkdir -p /etc/openstack/
sudo tee /etc/openstack/clouds.yaml >/dev/null <<'EOF'
clouds:
    mycloud:
        auth:
            auth_url: http://controller:5000/v3        # OS_AUTH_URL
            username: admin                            # OS_USERNAME
            password: password                         # OS_PASSWORD
            project_name: admin                        # OS_PROJECT_NAME
            user_domain_name: Default                  # OS_USER_DOMAIN_NAME
            project_domain_name: Default               # OS_PROJECT_DOMAIN_NAME
        interface: public                            # default; matches openrc
        identity_api_version: 3                      # OS_IDENTITY_API_VERSION
        image_api_version: 2                         # OS_IMAGE_API_VERSION
        region_name: RegionOne                       # add if your cloud uses regions
EOF

sudo chown root:root /etc/openstack/clouds.yaml
sudo chmod 777 /etc/openstack/clouds.yaml

# 编写 Exporter 脚本
sudo cp /root/openstack-script/scripts/monitor/py_os_exporter.py /opt/py_os_exporter/

sudo tee /etc/systemd/system/py_os_exporter.service >/dev/null <<'EOF'
[Unit]
Description=Python OpenStack Exporter
After=network.target

[Service]
WorkingDirectory=/opt/py_os_exporter
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/py_os_exporter/venv/bin/python /opt/py_os_exporter/py_os_exporter.py
Restart=on-failure
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
(venv) root@monitor:/opt/py_os_exporter#
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now py_os_exporter
sudo systemctl status py_os_exporter --no-pager

# 在/etc/prometheus/rules下创建alert_rules.yml 
cat <<EOF | sudo tee /etc/prometheus/rules/alert_rules.yml
groups:
- name: py-openstack-alerts     # ← 只包含 Python-Exporter 指标
  rules:

  # ── 1. 关键 API 服务存活性 ─────────────────────────────────────
  - alert: NovaAPIDown
    expr: openstack_service_up{service="nova-api"} == 0
    for: 2m
    labels: {severity: critical}
    annotations:
      summary: "nova-api 不可用，计算节点无法调度"

  - alert: GlanceAPIDown
    expr: openstack_service_up{service="glance-api"} == 0
    for: 5m
    labels: {severity: warning}
    annotations:
      summary: "glance-api 无响应，镜像上传/下载受影响"

  - alert: NeutronAPIDown
    expr: openstack_service_up{service="neutron-api"} == 0
    for: 2m
    labels: {severity: critical}
    annotations:
      summary: "neutron-api 不可用，网络创建与浮动 IP 分配将失败"

  # ── 2. 实例状态监控 ───────────────────────────────────────────
  - alert: ErrorInstanceFound
    expr: openstack_instances{status="ERROR"} > 0
    for: 5m
    labels: {severity: warning}
    annotations:
      summary: "发现 {{ $value }} 台 ERROR 状态虚拟机，需要人工排查"

  - alert: TooManyShutoff
    expr: openstack_instances{status="SHUTOFF"} > 20
    for: 30m
    labels: {severity: info}
    annotations:
      summary: "SHUTOFF 实例超过 20 台，可能存在资源浪费"

  # ── 3. 卷与容量 ───────────────────────────────────────────────
  - alert: CinderCapacity80
    expr: openstack_volume_capacity_bytes{type="used"}
          / openstack_volume_capacity_bytes{type="total"} > 0.8
    for: 10m
    labels: {severity: warning}
    annotations:
      summary: "Cinder 容量使用率超过 80%，请及时扩容或清理"

  - alert: VolumeCountHigh
    expr: openstack_volumes_total > 500
    for: 15m
    labels: {severity: info}
    annotations:
      summary: "卷数量超过 500，注意检查是否存在批量创建行为"

EOF
