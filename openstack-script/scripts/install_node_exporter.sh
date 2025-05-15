#!/bin/bash

# 从配置文件 config.ini 加载配置
source config.ini

# 函数：安装 Node Exporter
install_node_exporter() {
    echo -e "${YELLOW}开始安装 Node Exporter...${RESET}"

    # 从下载链接中提取版本号
    NODE_EXPORTER_VERSION=$(echo "$NODE_EXPORTER_URL" | grep -oP 'v\K[0-9.]+')

    if [ -z "$NODE_EXPORTER_VERSION" ]; then
        echo -e "${RED}无法从 URL 中提取版本号，请检查 URL 是否正确。${RESET}"
        exit 1
    fi

    echo -e "${YELLOW}检测到版本号：${NODE_EXPORTER_VERSION}${RESET}"

    # 下载并解压 Node Exporter
    wget $NODE_EXPORTER_URL -O node_exporter.tar.gz
    tar -xzf node_exporter.tar.gz
    sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64 /usr/local/node_exporter

    # 创建符号链接，方便执行
    sudo ln -s /usr/local/node_exporter/node_exporter /usr/local/bin/node_exporter

    # 清理下载的压缩包
    rm node_exporter.tar.gz

    echo -e "${GREEN}Node Exporter 安装成功。${RESET}"
}

# 函数：配置 Node Exporter 为 systemd 服务
configure_node_exporter_service() {
    echo -e "${YELLOW}正在配置 Node Exporter 为 systemd 服务...${RESET}"

    # 创建 systemd 服务文件
    sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载 systemd，启用并启动 Node Exporter 服务
    sudo systemctl daemon-reload
    sudo systemctl enable node_exporter
    sudo systemctl start node_exporter

    # 验证服务状态
    if systemctl is-active --quiet node_exporter; then
        echo -e "${GREEN}Node Exporter 服务已启动。${RESET}"
        echo -e "${GREEN}Node Exporter 可通过 http://<your-server-ip>:9100/metrics 访问。${RESET}"
    else
        echo -e "${RED}Node Exporter 服务启动失败。${RESET}"
        exit 1
    fi
}

# 按顺序执行函数
install_node_exporter
configure_node_exporter_service

echo -e "${GREEN}Node Exporter 安装并配置完成。${RESET}"
