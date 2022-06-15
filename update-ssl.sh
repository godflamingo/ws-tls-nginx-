#!/bin/bash

if [ ! -f "/root/.$1-expiredate" ]; then
  expire=`date -d $(certbot certificates -d $1 | grep "Expiry Date" | awk '{print$3}') +%s`
  echo $expire > /root/.$1-expiredate
else
  expire=`cat /root/.$1-expiredate`
fi

today=`date +%s`
if [ $today -ge $expire ]; then
  certbot renew --force-renewal --cert-name $1 --post-hook "systemctl restart nginx"
fi