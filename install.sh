#!/bin/bash

if [ `whoami` != "root" ]; then
  echo "Please run this script with root privileges!"
  exit
fi
read -p "Enter v2ray port (default: 12345; Just keep the default value if there is no port conflict):" v2rayPort
v2rayPort=${v2rayPort:-12345}

read -p "Enter nginx port (default: 443):" nginxPort
nginxPort=${nginxPort:-443}

read -p "Enter your domain name (required):" domainName
if [ ! -n "$domainName" ]; then
  echo "Domain name is required!"
  exit
fi
if [ "$(lsof -i:$v2rayPort)" -o "$(lsof -i:$nginxPort)" ]; then
  echo "Port $v2rayPort or $nginxPort is not available."
  exit
fi
echo -e "\nThe result of 'nslookup $domainName': \n\n"
nslookup $domainName
read -p "Your domain name has already resolved to the IP address of this server? [y/n] " input
case $input in
  [yY]*)
    echo -e "Great! Let's continue.\n"
    ;;
  [nN]*)
    echo "Please set a DNS resolution to point the domain name to the IP address of this server."
    echo "Run 'nslookup $domainName' to check."
    exit
    ;;
  *)
    echo "Just enter y or n, please."
    exit
    ;;
esac

uuid=`cat /proc/sys/kernel/random/uuid`
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
path=`cat /dev/urandom | head -n 10 | md5sum | head -c 5`
cat>/usr/local/etc/v2ray/config.json<<EOF
{
  "log":{
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $v2rayPort,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [{
          "id": "$uuid",
          "alterID": 0
        }]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/$path"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": [
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

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
infoStr=`echo "{\"v\": \"2\", \"ps\": \"$domainName\", \"add\": \"$domainName\", \"port\": \"$nginxPort\", \"id\": \"$uuid\", \"aid\": \"0\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"\", \"path\": \"/$path\", \"tls\": \"tls\", \"sni\": \"\"}" | base64 -w 0`
echo -e "Import the link shown below to your client software: \n\nvmess://$infoStr"
