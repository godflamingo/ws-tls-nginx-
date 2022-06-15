# 科学上网自建VPS（VMESS/VLESS + WebSocket + TLS + Nginx）脚本

关于通过VMESS/VLESS + WebSocket + TLS + Nginx方式进行科学上网的原理请自行谷歌。

为方便以后使用，随意写了一个安装脚本。

## 使用说明

### 预准备

- 一台具备公网IPv4地址的VPS服务器，操作系统： Ubuntu （已测试18.04与20.04）
- 域名（解析到VPS的IP）

### 使用方法
以root权限执行下面命令并根据脚本提示输入参数。参数分别为：

|参数|说明|
|:-:|:-:|
|protocol|V2Ray协议，支持VMESS与VLESS|
|v2ray port|V2Ray的监听端口，用以与服务器本地的Nginx通信，如无冲突则不需要改|
|nginx port|Nginx服务对外开放的端口，也即客户端与服务器通信的端口|
|domain name|你的域名|

```shell
bash <(curl -L https://raw.githubusercontent.com/windshadow233/ws-tls-nginx/main/install.sh)
```

该脚本中途使用Let's Encrypt生成证书，脚本会配置自动更新证书的crontab，每日零点检查证书是否将在今日过期，若如是，则更新。

证书更新逻辑：检查/root目录下是否存在.<span>$</span>{domainName}-expiredate文件（用以存放证书过期日期的时间戳），若存在则读取其中的时间戳，否则执行certbot命令检查过期日期并写入.<span>$</span>{domainName}-expiredate文件。

运行完成后，自动生成客户端配置链接。

部分客户端软件可能会无法识别VLESS链接，此时按链接给出的配置信息手动导入即可。
