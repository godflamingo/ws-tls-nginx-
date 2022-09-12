#!/bin/bash

if [ ! -f "/root/.$1-expire" ]; then
  expire=`date -d $(certbot certificates -d $1 | grep "Expiry Date" | awk '{print$3}') +%s`
  echo $expire > /root/.$1-expire
else
  expire=`cat /root/.$1-expire`
fi

today=`date +%s`
if [ $today -ge $((expire - 86400 * $2)) ]; then
  ufw allow 80
  certbot renew --cert-name $1 --deploy-hook "nginx -s reload"
  ufw deny 80
  expire=`date -d $(certbot certificates -d $1 | grep "Expiry Date" | awk '{print$3}') +%s`
  echo $expire > /root/.$1-expire
fi
