# 科学上网自建VPS（Vmess + WebSocket + TLS + Nginx）脚本

关于通过Vmess + WebSocket + TLS + Nginx方式进行科学上网的原理请自行谷歌。

为方便以后使用，随意写了一个安装脚本。

## 使用说明

### 预准备

- 一台VPS服务器，操作系统： Ubuntu 18.04
- 域名（解析到VPS的IP）

### 使用方法
以root权限执行下面命令并根据脚本提示输入参数。参数分别为：

|参数|说明|
|:-:|:-:|
|v2ray port|V2Ray的监听端口，用以与服务器本地的Nginx通信，如无冲突则不需要改|
|nginx port|Nginx服务对外开放的端口，也即客户端与服务器通信的端口|
|domain name|你的域名|

```shell
bash <(curl -L https://raw.githubusercontent.com/windshadow233/ws-tls-nginx/main/install.sh)
```

该脚本中途使用Let's Encrypt生成证书，需要每隔三个月续签一次。

运行完成后，自动生成客户端配置链接。
