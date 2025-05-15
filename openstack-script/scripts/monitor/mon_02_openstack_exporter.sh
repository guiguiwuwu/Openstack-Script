#!/bin/bash

# 加载配置文件 config.ini
source config.ini

# 函数：安装 OpenStack Exporter
install_exporter() {
    echo -e "${YELLOW}正在安装 OpenStack Exporter...${RESET}"

    # 下载并解压 OpenStack Exporter
    wget $EXPORTER_URL -O openstack-exporter.tar.gz
    tar -xzf openstack-exporter.tar.gz
    sudo mv openstack-exporter /usr/local/bin/
    rm openstack-exporter.tar.gz

    # 确认安装是否成功
    if [ -f /usr/local/bin/openstack-exporter ]; then
        echo -e "${GREEN}OpenStack Exporter 安装成功。${RESET}"
    else
        echo -e "${RED}OpenStack Exporter 安装失败。${RESET}"
        exit 1
    fi
}

# 函数：创建 OpenRC 文件
generate_openrc_files() {
    echo "${YELLOW}正在创建 /root/ 目录下的 admin-openrc 文件...${RESET}"

    # 创建 admin-openrc 文件
    sudo tee /root/admin-openrc > /dev/null << EOF
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

    echo "${GREEN}admin-openrc 文件已成功创建。${RESET}"
}

# 函数：创建配置文件 config.yaml
create_exporter_config() {
    echo -e "${YELLOW}正在为 OpenStack Exporter 创建配置文件 config.yaml...${RESET}"

    # 创建配置目录
    sudo mkdir -p /etc/openstack-exporter/

    # 创建配置文件 config.yaml
    sudo tee /etc/openstack-exporter/config.yaml > /dev/null <<EOF
clouds:
  my-cloud:
    region_name: RegionOne
    auth:
      auth_url: http://controller:5000/v3
      username: admin
      password: $ADMIN_PASS
      project_name: admin
      user_domain_name: Default
      project_domain_name: Default
    verify: false
EOF

    echo -e "${GREEN}配置文件已创建：/etc/openstack-exporter/config.yaml。${RESET}"
}

# 函数：设置 OpenStack Exporter 为 systemd 服务
setup_exporter_service() {
    echo -e "${YELLOW}正在将 OpenStack Exporter 设置为 systemd 服务...${RESET}"

    # 创建 systemd 服务文件
    sudo tee /etc/systemd/system/openstack-exporter.service > /dev/null <<EOF
[Unit]
Description=Prometheus OpenStack Exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/openstack-exporter --os-client-config /etc/openstack-exporter/config.yaml my-cloud
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载 systemd，启用并启动服务
    sudo systemctl daemon-reload
    sudo systemctl enable openstack-exporter
    sudo systemctl start openstack-exporter

    # 验证服务状态
    if systemctl is-active --quiet openstack-exporter; then
        echo -e "${GREEN}OpenStack Exporter 服务已启动。${RESET}"
    else
        echo -e "${RED}OpenStack Exporter 服务启动失败。${RESET}"
        exit 1
    fi
}

# 按顺序执行各个函数
install_exporter
generate_openrc_files
create_exporter_config
setup_exporter_service

echo -e "${GREEN}OpenStack Exporter 已成功安装并配置完成。${RESET}"
