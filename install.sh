#!/bin/bash

green='\033[0;32m'
plain='\033[0m'
yellow='\033[0;33m'
red='\033[0;31m'

function LOGD() {
  echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
  echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
  echo -e "${green}[INF] $* ${plain}"
}

[[ $EUID -ne 0 ]] && echo -e "${green}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

confirm() {
  if [[ $# > 1 ]]; then
    echo && read -p "$1 [默认$2]: " temp
    if [[ "${temp}" == "" ]]; then
      temp=$2
    fi
  else
    read -p "$1 [y/n]: " temp
  fi
  if [[ "${temp}" == "y" || "${temp}" == "Y" ]]; then
    return 0
  else
    return 1
  fi
}

tengine() {
  echo -e "${green}开始安装依赖软件包...${plain}"
  sudo apt install -y build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev

  TENGINE="/main/apps/tengine"
  if [ ! -d "$TENGINE" ]; then
    sudo mkdir -p $TENGINE
  fi

  cd $TENGINE

  echo -e "${green}开始下载源码...${plain}"
  version=$(curl -Ls "https://api.github.com/repos/alibaba/tengine/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  wget -N --no-check-certificate -O tengine-${version}.tar.gz https://github.com/alibaba/tengine/archive/refs/tags/${version}.tar.gz
  # wget -N --no-check-certificate https://tengine.taobao.org/download/tengine-${version}.tar.gz

  echo -e "${green}开始解压源码...${plain}"
  tar -zxvf tengine-${version}.tar.gz

  cd tengine-${version}

  echo -e "${green}开始配置编译选项...${plain}"
  ./configure --prefix=$TENGINE

  echo -e "${green}开始编译和安装...${plain}"
  sudo make install

  if ! grep -q "/main/apps/tengine/sbin/" /root/.bashrc; then
    echo 'export PATH="/main/apps/tengine/sbin/:$PATH"' | sudo tee -a /root/.bashrc
  fi

  sudo wget https://raw.githubusercontent.com/YNJFCN/Tengine-sh/main/service/nginx.service -O /etc/systemd/system/nginx.service
  sudo systemctl daemon-reload
  sudo systemctl enable nginx.service

  cd $TENGINE
  sudo rm -f tengine-${version}.tar.gz
  sudo rm -rf tengine-${version}

  source /root/.bashrc

  echo -e "${green}是否继续安装Nodejs?${plain}"
  confirm "[y/n] [默认n]"
  if [ $? -eq 0 ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    source /root/.bashrc
    source /root/.nvm/nvm.sh
    nvm install node
  fi

  echo -e "${green}安装完成.${plain}"
  menu
}

Certificate() {
  CF_Domain=""
  CF_GlobalKey=""
  CF_AccountEmail=""

  confirm "是否直接颁发证书[y/n]" "y"
  if [ $? -eq 0 ]; then
    LOGD "请设置要申请的域名:"
    read -p "Input your domain here:" CF_Domain
    LOGD "你的域名设置为:${CF_Domain}"
    issueCertificate

  else
    cd ~
    LOGI "安装Acme脚本"
    curl https://get.acme.sh | sh
    source ~/.bashrc
    if [ $? -ne 0 ]; then
      LOGE "安装acme脚本失败"
      exit 1
    fi
    LOGD "请设置域名:"
    read -p "Input your domain here:" CF_Domain
    LOGD "你的域名设置为:${CF_Domain}"
    LOGD "请设置API密钥:"
    read -p "Input your key here:" CF_GlobalKey
    LOGD "你的API密钥为:${CF_GlobalKey}"
    LOGD "请设置注册邮箱:"
    read -p "Input your email here:" CF_AccountEmail
    LOGD "你的注册邮箱为:${CF_AccountEmail}"
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    if [ $? -ne 0 ]; then
      LOGE "修改默认CA为Lets'Encrypt失败,脚本退出"
      exit 1
    fi
    export CF_Key="${CF_GlobalKey}"
    export CF_Email=${CF_AccountEmail}
    issueCertificate
  fi

  menu
}

issueCertificate() {
  certPath=/root/Certificate/${CF_Domain}

  ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
  if [ $? -ne 0 ]; then
    LOGE "修改默认CA为Lets'Encrypt失败,脚本退出"
    exit 1
  fi

  ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log
  if [ $? -ne 0 ]; then
    LOGE "证书签发失败,脚本退出"
    exit 1
  else
    LOGI "证书签发成功,安装中..."
  fi

  rm -rf $certPath

  if [ ! -d "$certPath" ]; then
    sudo mkdir -p $certPath
  fi

  ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} --ca-file ${certPath}/ca.cer \
    --cert-file ${certPath}/${CF_Domain}.cer --key-file ${certPath}/${CF_Domain}.key \
    --fullchain-file ${certPath}/fullchain.cer
  if [ $? -ne 0 ]; then
    LOGE "证书安装失败,脚本退出"
    exit 1
  else
    LOGI "证书安装成功,开启自动更新..."
    LOGI "安装路径为${certPath}"
  fi

  ~/.acme.sh/acme.sh --upgrade --auto-upgrade
  if [ $? -ne 0 ]; then
    LOGE "自动更新设置失败,脚本退出"
    ls -lah $certPath
    chmod 755 $certPath
    exit 1
  else
    LOGI "证书已安装且已开启自动更新,具体信息如下"
    ls -lah $certPath
    chmod 755 $certPath
  fi
  menu
}

renew() {
  echo -e "${green}开始更新软件包...${plain}"
  sudo apt update -y

  echo -e "${green}开始升级软件包...${plain}"
  sudo apt upgrade -y

  menu
}

mysql() {
  LOGI "安装MySQL"
  apt update -y
  apt install mysql-server -y
  if [ $? -ne 0 ]; then
    LOGE "Mysql安装失败,脚本退出"
    menu
  fi

  LOGI "启动MySQL"
  service mysql start
  if [ $? -ne 0 ]; then
    LOGE "Mysql启动失败,脚本退出"
    menu
  fi

  LOGI "启用开机自启动"
  sudo systemctl enable mysql
  if [ $? -ne 0 ]; then
    LOGE "自启动设置失败,脚本退出"
    menu
  fi

  LOGI "MySQL状态"
  sudo service mysql status

  menu
}

postgresql() {
  postgresqlMenu
  menu

  installPostgresql() {
    LOGI "安装postgresql"
    if ! apt install postgresql -y; then
      LOGE "安装postgresql失败 脚本退出"
    fi

    LOGI "postgresql运行状态"
    if ! sudo systemctl status postgresql; then
      LOGE "运行状态异常"
    fi

    postgresqlMenu
  }

  postgresqlMenu() {
    LOGI "1. ------- 安装"
    LOGI "2. ------- 更新"
    LOGI "4. ------- 添加用户"
    LOGI "4. ------- 移除用户"
    LOGI "4. ------- 新增访问权限"
    read -p -r "请输入选择 [0-16] Enter退出: " OPTION
    case $OPTION in
    1)
      installPostgresql
      ;;
    *)
      exit 1
      ;;
    esac
  }
}

menu() {
  echo -e ""
  LOGD " Ubuntu && Debian "
  LOGD "————————————————"
  LOGI "1. ------- 安装 Tengine"
  LOGI "2. ------- 更新 & 升级 软件包"
  LOGI "3. ------- 申请SSL证书(acme申请)"
  LOGI "4. ------- 安装 Mysql"
  LOGI "5. ------- Postgresql"
  read -p -r "请输入选择 [0-16] Enter退出: " ORDER

  case $ORDER in
  1)
    tengine
    ;;
  2)
    renew
    ;;
  3)
    Certificate
    ;;
  4)
    mysql
    ;;
  5)
    postgresql
    ;;
  *)
    history -c
    exit 1
    ;;
  esac
}

menu
