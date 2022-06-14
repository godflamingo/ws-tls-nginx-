#!/bin/bash

if [ `whoami` != "root" ]; then
  echo "Please run this script with root privileges!"
  exit
fi
read -p $'1. VMESS\x0a2. VLESS\x0aSelect protocol: ' protocol
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
v2rayPort=${v2rayPort:-12345}
if [[ $v2rayPort -le 0 ]] || [[ $v2rayPort -gt 65535 ]]; then
  echo "The v2ray port value must be between 1 and 65535."
  exit 1
fi

read -p $'Enter nginx port (default: 443): ' nginxPort
nginxPort=${nginxPort:-443}
if [[ $nginxPort -le 0 ]] || [[ $nginxPort -gt 65535 ]]; then
  echo "The nginx port value must be between 1 and 65535."
  exit 1
fi

if [ "$(lsof -i:$v2rayPort)" -o "$(lsof -i:$nginxPort)" ]; then
  echo "Port $v2rayPort or $nginxPort is not available."
  exit
fi
export v2rayPort
export nginxPort

read -p $'Enter your domain name (required): ' domainName
if [ ! -n "$domainName" ]; then
  echo "Domain name is required!"
  exit
fi
export domainName

echo -e "\nResoving your domain name...\n"
dns_ip=`curl -s ipget.net/?ip=$domainName`
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

echo -e "Waiting for 'apt-get update'...\n"
apt-get update -qq
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
  apt-get -yqq install certbot
fi

if [ "$(command -v certbot)" ]; then
  echo -e "Certbot was installed.\n"
else
  echo "Certbot installation failed, please check."
  exit
fi

if [ ! "$(command -v nginx)" ]; then
  echo -e "Installing Nginx...\n"
  apt-get -yqq install nginx
fi

if [ "$(command -v nginx)" ]; then
  echo -e "Nginx was installed.\n"
else
  echo "Nginx installation failed, please check."
  exit
fi

echo -e "Writing v2ray config...\n"
export uuid=`cat /proc/sys/kernel/random/uuid`
export path=`head -n 10 /dev/urandom | md5sum | head -c $((RANDOM % 10 + 4))`
curl -sL https://raw.githubusercontent.com/windshadow233/ws-tls-nginx/main/config/v2ray_$protocol.json -o /usr/local/etc/v2ray/config.json.template
envsubst '${v2rayPort}${uuid}${path}' < /usr/local/etc/v2ray/config.json.template > /usr/local/etc/v2ray/config.json
rm /usr/local/etc/v2ray/config.json.template

echo -e "Fetching SSL certificates...\n"
ufw allow 80
echo -e 'A' | certbot certonly --register-unsafely-without-email --webroot -w /var/www/html --preferred-challenges http -d $domainName
ufw deny 80

certificates=`certbot certificates | grep $domainName`
if [ "$certificates" ]; then
  echo -e "Certificates were installed successfully!\n"
else
  echo "Certificates installation failed, please check."
  exit
fi

echo -e "Writing nginx config...\n"
cat>/etc/nginx/conf.d/v2ray.conf<<EOF
server {
  listen $nginxPort ssl;
  ssl on;
  ssl_certificate       /etc/letsencrypt/live/$domainName/fullchain.pem;
  ssl_certificate_key   /etc/letsencrypt/live/$domainName/privkey.pem;
  ssl_protocols         TLSv1 TLSv1.1 TLSv1.2;
  ssl_ciphers           HIGH:!aNULL:!MD5;
  server_name           $domainName;
  location /$path {
    proxy_redirect off;
    proxy_pass http://127.0.0.1:$v2rayPort;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$http_host;

    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}
EOF

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
    infoStr="$uuid@$domainName:$nginxPort?allowInsecure=false&path=%2F$path&security=tls&type=ws#$domainName"
    ;;
esac
echo -e "Import the link shown below to your client software: \n\n$protocol://$infoStr"
