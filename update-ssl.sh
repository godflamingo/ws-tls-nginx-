#!/bin/bash

if [ ! -f "/root/.expire-date" ]; then
  expire=`date -d $(certbot certificates -d $1 | grep "Expiry Date" | awk '{print$3}') +%s`
  echo $expire > /root/.expire-date
else
  expire=`cat /root/.expire-date`
fi

today=`date +%s`
if [ $today -ge $expire ]; then
  certbot renew --force-renewal --cert-name $1 --post-hook "systemctl restart nginx"
fi