#!/bin/bash

# 安装必要的依赖包
install_dependencies() {
    echo -e "${YELLOW}正在安装必要的依赖包...${RESET}"
    sudo apt-get install -y apt-transport-https software-properties-common wget gpg
    echo -e "${GREEN}依赖包安装成功。${RESET}"
}

# 添加 Grafana 的 GPG 密钥
add_grafana_gpg_key() {
    echo -e "${YELLOW}正在添加 Grafana 的 GPG 密钥...${RESET}"
    sudo mkdir -p /etc/apt/keyrings/
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
    echo -e "${GREEN}Grafana 的 GPG 密钥添加成功。${RESET}"
}

# 添加 Grafana 软件源
configure_grafana_repository() {
    echo -e "${YELLOW}正在配置 Grafana 软件源...${RESET}"
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
    echo -e "${GREEN}Grafana 软件源配置成功。${RESET}"
}

# 更新软件包列表
update_apt_sources() {
    echo -e "${YELLOW}正在更新软件包列表...${RESET}"
    sudo apt-get update
    echo -e "${GREEN}软件包列表更新成功。${RESET}"
}

# 安装 Grafana
install_grafana_package() {
    echo -e "${YELLOW}正在安装 Grafana...${RESET}"
    sudo apt-get install -y grafana
    echo -e "${GREEN}Grafana 安装成功。${RESET}"
}

# 启动并设置 Grafana 服务
start_and_enable_grafana() {
    echo -e "${YELLOW}正在启动并设置 Grafana 服务...${RESET}"
    sudo systemctl start grafana-server
    sudo systemctl enable grafana-server
    echo -e "${GREEN}Grafana 服务已启动并设置为开机自启。${RESET}"
    echo -e "${GREEN}您可以通过 http://<your-server-ip>:3000 访问 Grafana（默认用户名：admin，密码：admin）。${RESET}"
}

# 按顺序执行所有函数
install_dependencies
add_grafana_gpg_key
configure_grafana_repository
update_apt_sources
install_grafana_package
start_and_enable_grafana

echo -e "${GREEN}Grafana 安装和配置已成功完成。${RESET}"
