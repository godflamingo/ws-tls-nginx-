#!/bin/bash

if [ `whoami` != "root" ]; then
  echo "Please run this script with root privileges!"
  exit
fi
read -p $'Select protocol:\x0a1. VMESS\x0a2. VLESS\x0aChoose 1 or 2: ' protocol
case $protocol in
  1)
    protocol=vmess
    ;;
  2)
    protocol=vless
    ;;
  *)
    echo "Wrong input!"
    exit
esac
 
read -p $'Enter v2ray port (default: 12345)\x0aJust keep the default value if there is no port conflict): ' v2rayPort
export v2rayPort=${v2rayPort:-12345}
if [[ $v2rayPort -le 0 ]] || [[ $v2rayPort -gt 65535 ]]; then
  echo "The v2ray port value must be between 1 and 65535."
  exit 1
fi

read -p $'Enter nginx port (default: 443): ' nginxPort
export nginxPort=${nginxPort:-443}
if [[ $nginxPort -le 0 ]] || [[ $nginxPort -gt 65535 ]]; then
  echo "The nginx port value must be between 1 and 65535."
  exit 1
fi

if [ "$(lsof -i:$v2rayPort | grep LISTEN)" -o "$(lsof -i:$nginxPort | grep LISTEN)" ]; then
  echo "Port $v2rayPort or $nginxPort is not available."
  exit
fi

read -p $'Enter your domain name (required): ' domainName
if [ ! -n "$domainName" ]; then
  echo "Domain name is required!"
  exit
fi
export domainName

echo -e "\nResoving your domain name...\n"
dns_ip=`dig A $domainName +short | tail -n 1`
echo -e "Fetching your VPS ip address...\n"
vps_ip=`curl -s4 https://ipget.net`
echo -e "Your domain name is resolved to: $dns_ip\nYour VPS ip address: $vps_ip\n"
if [ $dns_ip == $vps_ip ]; then
  echo -e "Your domain name has already resolved to the IP address of this VPS! Let's continue.\n"
else
  echo "Please resolve your domain name to the IP address of this VPS first, and then run this script again."
  echo "Run 'nslookup $domainName' to check."
  exit
fi

echo -e "Run 'apt-get update'...\n"
apt-get update
if [ ! "$(command -v v2ray)" ]; then
  echo -e "Installing V2Ray...\n"
  bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
fi

if [ "$(command -v v2ray)" ]; then
  echo -e "V2Ray was installed.\n"
else
  echo "V2Ray installation failed, please check."
  exit
fi

if [ ! "$(command -v certbot)" ]; then
  echo -e "Installing Certbot...\n"
  apt-get -y install certbot
fi

if [ "$(command -v certbot)" ]; then
  echo -e "Certbot was installed.\n"
else
  echo "Certbot installation failed, please check."
  exit
fi

if [ ! "$(command -v nginx)" ]; then
  echo -e "Installing Nginx...\n"
  apt-get -y install nginx
fi

if [ "$(command -v nginx)" ]; then
  echo -e "Nginx was installed.\n"
else
  echo "Nginx installation failed, please check."
  exit
fi

echo -e "Downloading v2ray config...\n"
export uuid=`cat /proc/sys/kernel/random/uuid`
export path=`head -n 10 /dev/urandom | md5sum | head -c $((RANDOM % 10 + 4))`
curl -sL https://raw.githubusercontent.com/windshadow233/ws-tls-nginx/main/config/v2ray_$protocol.json -o /usr/local/etc/v2ray/config.json.template
envsubst '${v2rayPort}${uuid}${path}' < /usr/local/etc/v2ray/config.json.template > /usr/local/etc/v2ray/config.json
rm /usr/local/etc/v2ray/config.json.template

echo -e "Fetching SSL certificate...\n"
ufw allow 80
echo -e 'A' | certbot certonly --register-unsafely-without-email --webroot -w /var/www/html --preferred-challenges http -d $domainName
ufw deny 80

certificates=`certbot certificates | grep $domainName`
if [ "$certificates" ]; then
  echo -e "Certificate was installed successfully!\n"
else
  echo "Certificate installation failed, please check."
  exit
fi

echo -e "Downloading nginx config...\n"
curl -sL https://raw.githubusercontent.com/windshadow233/ws-tls-nginx/main/config/nginx.conf -o /etc/nginx/conf.d/v2ray.conf.template
envsubst '${v2rayPort}${nginxPort}${domainName}${path}' < /etc/nginx/conf.d/v2ray.conf.template > /etc/nginx/conf.d/v2ray.conf
rm /etc/nginx/conf.d/v2ray.conf.template

echo -e "Downloading certificate automatic renewal script...\n"
curl -s https://raw.githubusercontent.com/windshadow233/ws-tls-nginx/main/renew-cert.sh -o /root/update-ssl.sh
chmod +x /root/update-ssl.sh
echo -e "Writing certificate automatic renewal task into /etc/crontab..."
echo "0 0 * * * root /root/renew-cert.sh $domainName 5" >> /etc/crontab

echo -e "Restarting all services...\n"
systemctl daemon-reload
systemctl restart v2ray
systemctl restart nginx
systemctl enable v2ray
systemctl enable nginx
ufw allow $nginxPort
echo -e "Finish! \nV2Ray config file is at: /usr/local/etc/v2ray/config.json\nNginx config file is at: /etc/nginx/conf.d/v2ray.conf\n"
case $protocol in
  vmess)
    infoStr=`echo "{\"v\": \"2\", \"ps\": \"$domainName\", \"add\": \"$domainName\", \"port\": \"$nginxPort\", \"id\": \"$uuid\", \"aid\": \"0\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"\", \"path\": \"/$path\", \"tls\": \"tls\", \"sni\": \"\"}" | base64 -w 0`
    ;;
  vless)
    infoStr="$uuid@$domainName:$nginxPort?encryption=none&allowInsecure=false&path=%2F$path&security=tls&type=ws#$domainName"
    ;;
esac
echo -e "Import the link shown below to your client software: \n\n$protocol://$infoStr"
