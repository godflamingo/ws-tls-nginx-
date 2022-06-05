#!/bin/bash

current_user=$(whoami)
if [ "$current_user" != "root" ]; then
  echo "Please run this script with root privileges!"
  exit
fi
read -p "Enter v2ray port (default: 12345):" v2rayPort
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

read -p "Your domain name has already resolved to the IP address of this server [y/n] " input
case $input in
  [yY]*)
    echo "Great! Let's continue."
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
apt-get update
if [ ! "$(command -v v2ray)" ]; then
  echo "Installing V2Ray..."
  bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
fi

if [ "$(command -v v2ray)" ]; then
  echo "V2Ray installed."
else
  echo "V2Ray installation has failed, please check."
  exit
fi

if [ ! "$(command -v nginx)" ]; then
  echo "Installing Nginx..."
  apt-get -y install nginx
fi

if [ "$(command -v nginx)" ]; then
  echo "Nginx installed."
else
  echo "Nginx installation has failed, please check."
  exit
fi

if [ ! "$(command -v certbot)" ]; then
  echo "Installing Certbot..."
  apt-get -y install certbot
fi

if [ "$(command -v certbot)" ]; then
  echo "Certbot installed."
else
  echo "Certbot installation has failed, please check."
  exit
fi

echo "Writing v2ray config..."
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
          "path": "/v2ray"
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

echo "Writing nginx config..."
cat>/etc/nginx/conf.d/v2ray.conf<<EOF
server {
  listen  $nginxPort ssl;
  ssl on;
  ssl_certificate       /etc/letsencrypt/live/$domainName/fullchain.pem;
  ssl_certificate_key   /etc/letsencrypt/live/$domainName/privkey.pem;
  ssl_protocols         TLSv1 TLSv1.1 TLSv1.2;
  ssl_ciphers           HIGH:!aNULL:!MD5;
  server_name           $domainName;
  location /v2ray {
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

echo "Fetching SSL certificates..."
ufw allow 80
echo -e 'A' | certbot certonly --register-unsafely-without-email --webroot --preferred-challenges http -d $domainName
ufw deny 80

certificates=`certbot certificates | grep $domainName`
if [ "$certificates" ]; then
  echo "Certificates installed successfully!"
else
  echo "Certificates installation failed, please check."
  exit
fi

echo "Restarting all services..."
systemctl daemon-reload
systemctl restart v2ray
systemctl restart nginx
systemctl enable v2ray
systemctl enable nginx
ufw allow $nginxPort
echo "Finish! V2Ray config file is at: /usr/local/etc/v2ray/config.json and Nginx config file is at: /etc/nginx/conf.d/v2ray.conf."
infoStr=`echo "{\"v\": \"2\", \"ps\": \"$domainName\", \"add\": \"$domainName\", \"port\": \"$nginxPort\", \"id\": \"$uuid\", \"aid\": \"0\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"\", \"path\": \"/v2ray\", \"tls\": \"true\", \"sni\": \"\"}" | base64 -w 0`
echo -e "Import the link shown below to your client software: \n\nvmess://$infoStr"
