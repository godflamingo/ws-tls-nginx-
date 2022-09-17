# 科学上网自建VPS（VMESS/VLESS + WebSocket + TLS + Nginx）脚本

关于通过VMESS/VLESS + WebSocket + TLS + Nginx方式进行科学上网的原理请自行谷歌。

为方便以后使用，随意写了一个安装脚本。

## 使用说明

### 预准备

- 一台具备公网IPv4地址的VPS服务器，操作系统： Ubuntu （已测试18.04与20.04）
- 域名（解析到VPS的IP）

### 使用方法
以root权限执行下面命令并根据脚本提示输入参数。

```shell
bash <(curl -L https://raw.githubusercontent.com/windshadow233/ws-tls-nginx/main/install.sh)
```

参数分别为：

|参数|说明|
|:-:|:-:|
|protocol|V2Ray协议，支持VMESS与VLESS|
|v2ray port|V2Ray的监听端口，用以与服务器本地的Nginx通信，如无冲突则不需要改|
|nginx port|Nginx服务对外开放的端口，也即客户端与服务器通信的端口|
|domain name|你的域名|


该脚本中途使用Let's Encrypt生成证书，脚本会配置自动更新证书的crontab，每日零点检查证书是否将在n天以后过期，若是，则更新。（n默认为5，如需修改，请在/etc/crontab中修改函数参数，该值默认情况下不应超过30）。

证书更新逻辑：
1. 检查/root目录下是否存在.<span>$</span>{domainName}-expire文件（用以存放证书过期日期的时间戳），若存在则读取其中的时间戳，否则执行certbot获取检查过期日期并写入.<span>$</span>{domainName}-expire文件。
2. 判断当前时间戳是否满足提前天数条件，若为真，则更新证书与时间戳文件。

**注意：80端口将被用于以web-root的方式续约证书，因此在选择V2Ray、Nginx端口时请避开80。**

运行完成后，自动生成客户端配置链接。

部分客户端软件可能会无法识别VLESS链接，此时按链接给出的配置信息手动导入即可。
