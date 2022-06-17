#!/bin/bash

GREEN="\033[36m"
RED="\033[31m"
YELLOW="\033[32m"
RESET="\033[0m"

if [ `whoami` != "root" ]; then
  echo -e "${RED}Please run this script with root privileges!${RESET}"
  exit
fi
read -p $'\033[36mSelect protocol:\x0a1. VMESS\x0a2. VLESS\x0aChoose 1 or 2: \033[0m' protocol
case $protocol in
  1)
    protocol=vmess
    ;;
  2)
    protocol=vless
    ;;
  *)
    echo -e "${RED}Wrong input!${RESET}"
    exit
esac
echo -e "${GREEN}Enter ports${RESET}"
echo -e "${RED}DO NOT USE 80 ! ! !${RESET}"
read -p $'\033[36mEnter v2ray port (default: 12345)\x0aJust keep the default value if there is no port conflict): \033[0m' v2rayPort
export v2rayPort=${v2rayPort:-12345}
if [ $v2rayPort -le 0 ] || [ $v2rayPort -gt 65535 ] || [ $v2rayPort -eq 80 ]; then
  echo -e "${RED}The v2ray port value must be between 1 and 65535. And DO NOT USE 80 ! ! !"
  exit 1
fi

read -p $'\033[36mEnter nginx port (default: 443): \033[0m' nginxPort
export nginxPort=${nginxPort:-443}
if [ $nginxPort -le 0 ] || [ $nginxPort -gt 65535 ] || [ $nginxPort -eq 80 ]; then
  echo -e "${RED}The nginx port value must be between 1 and 65535. And DO NOT USE 80 ! ! !${RESET}"
  exit 1
fi

if [ "$(lsof -i:$v2rayPort | grep LISTEN)" -o "$(lsof -i:$nginxPort | grep LISTEN)" ]; then
  echo -e "${RED}Port $v2rayPort or $nginxPort is not available.${RESET}"
  exit
fi

read -p $'\033[36mEnter your domain name (required): \033[0m' domainName
if [ ! -n "$domainName" ]; then
  echo -e "${RED}Domain name is required!${RESET}"
  exit
fi
export domainName

echo -e "${GREEN}\nResoving your domain name...\n${RESET}"
dns_ip=`dig A $domainName +short | tail -n 1`
echo -e "${GREEN}Fetching your VPS ip address...\n${RESET}"
vps_ip=`curl -s4 https://ipget.net`
echo -e "${GREEN}Your domain name is resolved to: $dns_ip\nYour VPS ip address: $vps_ip\n${RESET}"
if [ $dns_ip == $vps_ip ]; then
  echo -e "${GREEN}Your domain name has already resolved to the IP address of this VPS! Let's continue.\n${RESET}"
else
  echo -e "${RED}Please resolve your domain name to the IP address of this VPS first, and then run this script again.${RESET}"
  echo -e "${RED}Run 'nslookup $domainName' to check.${RESET}"
  exit
fi

echo -e "${GREEN}Run 'apt-get update'...\n${RESET}"
apt-get update
if [ ! "$(command -v v2ray)" ]; then
  echo -e "${GREEN}Installing V2Ray...\n${RESET}"
  bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
fi

if [ "$(command -v v2ray)" ]; then
  echo -e "${GREEN}V2Ray was installed.\n${RESET}"
else
  echo -e "${RED}V2Ray installation failed, please check.${RESET}"
  exit
fi

if [ ! "$(command -v certbot)" ]; then
  echo -e "${GREEN}Installing Certbot...\n${RESET}"
  apt-get -y install certbot
fi

if [ "$(command -v certbot)" ]; then
  echo -e "${GREEN}Certbot was installed.\n${RESET}"
else
  echo -e "${RED}Certbot installation failed, please check.${RESET}"
  exit
fi

if [ ! "$(command -v nginx)" ]; then
  echo -e "${GREEN}Installing Nginx...\n${RESET}"
  apt-get -y install nginx
fi

if [ "$(command -v nginx)" ]; then
  echo -e "${GREEN}Nginx was installed.\n${RESET}"
else
  echo -e "${RED}Nginx installation failed, please check.${RESET}"
  exit
fi

echo -e "${GREEN}Downloading v2ray config...\n${RESET}"
export uuid=`cat /proc/sys/kernel/random/uuid`
export path=`head -n 10 /dev/urandom | md5sum | head -c $((RANDOM % 10 + 4))`
curl -sL https://raw.githubusercontent.com/windshadow233/ws-tls-nginx/main/config/v2ray_$protocol.json -o /usr/local/etc/v2ray/config.json.template
envsubst '${v2rayPort}${uuid}${path}' < /usr/local/etc/v2ray/config.json.template > /usr/local/etc/v2ray/config.json
rm /usr/local/etc/v2ray/config.json.template

echo -e "${GREEN}Fetching SSL certificate...\n${RESET}"
ufw allow 80
echo -e 'A' | certbot certonly --register-unsafely-without-email --webroot -w /var/www/html --preferred-challenges http -d $domainName
ufw deny 80

certificates=`certbot certificates | grep $domainName`
if [ "$certificates" ]; then
  echo -e "${GREEN}Certificate was installed successfully! \n${RESET}"
else
  echo -e "${RED}Certificate installation failed, please check.${RESET}"
  exit
fi

echo -e "${GREEN}Downloading nginx config...\n${RESET}"
curl -sL https://raw.githubusercontent.com/windshadow233/ws-tls-nginx/main/config/nginx.conf -o /etc/nginx/conf.d/v2ray.conf.template
envsubst '${v2rayPort}${nginxPort}${domainName}${path}' < /etc/nginx/conf.d/v2ray.conf.template > /etc/nginx/conf.d/v2ray.conf
rm /etc/nginx/conf.d/v2ray.conf.template

echo -e "${GREEN}Downloading certificate automatic renewal script...\n${RESET}"
curl -s https://raw.githubusercontent.com/windshadow233/ws-tls-nginx/main/renew-cert.sh -o /root/update-ssl.sh
chmod +x /root/update-ssl.sh
echo -e "${GREEN}Writing certificate automatic renewal task into /etc/crontab...${RESET}"
echo "0 0 * * * root /root/renew-cert.sh $domainName 5" >> /etc/crontab

echo -e "${GREEN}Restarting all services...\n${RESET}"
systemctl daemon-reload
systemctl restart v2ray
systemctl restart nginx
systemctl enable v2ray
systemctl enable nginx
ufw allow $nginxPort
echo -e "${GREEN}Finish! \nV2Ray config file is at: ${YELLOW}/usr/local/etc/v2ray/config.json\n${GREEN}Nginx config file is at: ${YELLOW}/etc/nginx/conf.d/v2ray.conf\n${RESET}"
case $protocol in
  vmess)
    infoStr=`echo "{\"v\": \"2\", \"ps\": \"$domainName\", \"add\": \"$domainName\", \"port\": \"$nginxPort\", \"id\": \"$uuid\", \"aid\": \"0\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"\", \"path\": \"/$path\", \"tls\": \"tls\", \"sni\": \"\"}" | base64 -w 0`
    ;;
  vless)
    infoStr="$uuid@$domainName:$nginxPort?encryption=none&allowInsecure=false&path=%2F$path&security=tls&type=ws#$domainName"
    ;;
esac
echo -e "${YELLOW}Import the link shown below to your client software: \n\n$protocol://$infoStr${RESET}"
