#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "注意: 请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "目前你的VPS的操作系统暂未支持！" && exit 1

archAffix(){
    case "$(uname -m)" in
        x86_64 | amd64) echo 'amd64' ;;
        armv8 | arm64 | aarch64) echo 'arm64' ;;
        *) red " 不支持的CPU架构！" && exit 1 ;;
    esac
    return 0
}

install_singbox(){
    if [[ $SYSTEM == "CentOS" ]]; then
        wget -N --no-check-certificate https://cdn.jsdelivr.net/gh/taffychan/sing-box/files/sing-box-latest-$(archAffix).rpm
        rpm -i sing-box-latest-$(archAffix).rpm
        rm -f sing-box-latest-$(archAffix).rpm
    else
        wget -N --no-check-certificate https://cdn.jsdelivr.net/gh/taffychan/sing-box/files/sing-box-latest-$(archAffix).deb
        dpkg -i sing-box-latest-$(archAffix).deb
        rm -f sing-box-latest-$(archAffix).deb
    fi

    rm -f /etc/sing-box/config.json
    wget --no-check-certificate -O /etc/sing-box/config.json https://raw.githubusercontent.com/taffychan/sing-box/main/configs/server.json
    
    mkdir /root/sing-box
    wget --no-check-certificate -O /root/sing-box/client-sockshttp.json https://raw.githubusercontent.com/taffychan/sing-box/main/configs/client-sockshttp.json
    wget --no-check-certificate -O /root/sing-box/client-tun.json https://raw.githubusercontent.com/taffychan/sing-box/main/configs/client-tun.json
    
    v6=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
    v4=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p)
    
    if [[ -n $v4 ]]; then
        sed -i "s/填写服务器ip地址/$v4/g" /root/sing-box/client-sockshttp.json
        sed -i "s/填写服务器ip地址/$v4/g" /root/sing-box/client-tun.json
    elif [[ -n $v6 ]]; then
        sed -i "s/填写服务器ip地址/$v6/g" /root/sing-box/client-sockshttp.json
        sed -i "s/填写服务器ip地址/$v6/g" /root/sing-box/client-tun.json
    fi
    
    current_pass=$(cat /etc/sing-box/config.json | grep password | awk '{print $2}' | awk -F '"' '{print $2}')
    yellow "为了确保连接安全性，故第一次安装需要设置Sing-box的连接密码"
    read -rp "请输入 Sing-box 的连接密码 [默认随机生成]: " new_pass
    [[ -z $new_pass ]] && new_pass=$(openssl rand -base64 32)
    systemctl stop sing-box
    sed -i "17s/$current_pass/$new_pass/g" /etc/sing-box/config.json
    sed -i "14s/$current_pass/$new_pass/g" /root/sing-box/client-sockshttp.json
    sed -i "34s/$current_pass/$new_pass/g" /root/sing-box/client-tun.json
    
    systemctl start sing-box
    systemctl enable sing-box

    if [[ -n $(service sing-box status 2>/dev/null | grep "inactive") ]]; then
        red "Sing-box 安装失败"
    elif [[ -n $(service sing-box status 2>/dev/null | grep "active") ]]; then
        green "Sing-box 安装成功"
        yellow "客户端Socks / HTTP代理模式配置文件已保存到 /root/sing-box/client-sockshttp.json"
        yellow "客户端TUN模式配置文件已保存到 /root/sing-box/client-tun.json"
    fi
}

uninstall_singbox(){
    systemctl stop sing-box
    systemctl disable sing-box
    rm -rf /root/sing-box
    ${PACKAGE_UNINSTALL} sing-box
    green "Sing-box 已彻底卸载完成"
}

change_password(){
    current_pass=$(cat /etc/sing-box/config.json | grep password | awk '{print $2}' | awk -F '"' '{print $2}')
    read -rp "请输入 Sing-box 的连接密码 [默认随机生成]: " new_pass
    [[ -z $new_pass ]] && new_pass=$(openssl rand -base64 32)
    systemctl stop sing-box
    sed -i "17s/$current_pass/$new_pass/g" /etc/sing-box/config.json
    sed -i "14s/$current_pass/$new_pass/g" /root/sing-box/client-sockshttp.json
    sed -i "34s/$current_pass/$new_pass/g" /root/sing-box/client-tun.json
    systemctl start sing-box
    green "Sing-box 连接密码更改为：${new_pass} 成功！"
    yellow "配置文件已更新，请重新在客户端导入节点或配置文件"
}

start_singbox() {
    systemctl start sing-box
    green "Sing-box 已启动！"
}

stop_singbox() {
    systemctl stop sing-box
    green "Sing-box 已停止！"
}

restart_singbox(){
    systemctl restart sing-box
    green "Sing-box 已重启！"
}

menu(){
    clear
    echo "#############################################################"
    echo -e "#                   ${RED} Sing-box  一键管理脚本${PLAIN}                  #"
    echo -e "# ${GREEN}作者${PLAIN}: taffychan                                           #"
    echo -e "# ${GREEN}GitHub${PLAIN}: https://github.com/taffychan                      #"
    echo "#############################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 安装 Sing-box"
    echo -e " ${GREEN}2.${PLAIN} ${RED}卸载 Sing-box${PLAIN}"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} 修改 Sing-box 连接密码"
    echo " -------------"
    echo -e " ${GREEN}4.${PLAIN} 启动 Sing-box"
    echo -e " ${GREEN}5.${PLAIN} 重启 Sing-box"
    echo -e " ${GREEN}6.${PLAIN} 停止 Sing-box"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} 退出"
    echo ""
    read -rp "请输入选项 [0-6]：" menuChoice
    case $menuChoice in
        1) install_singbox ;;
        2) uninstall_singbox ;;
        3) change_password ;;
        4) start_singbox ;;
        5) restart_singbox ;;
        6) stop_singbox ;;
        *) exit 1 ;;
    esac
}

menu
