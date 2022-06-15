#!/bin/bash

expire=`date -d $(certbot certificates -d $1 | grep "Expiry Date" | awk '{print$3}') +%s`
today=`date +%s`

if [ $today -ge expire ]; then
  certbot renew --force-renewal --post-hook "systemctl restart nginx"
fi