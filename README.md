## Mosdns update Cloudflare CDN

- 此脚本用于更新 mosdns 配置文件中的 Cloudflare CDN IP，详见https://github.com/XIU2/CloudflareSpeedTest/discussions/317
- 适用 mosdns 版本：v5，先前版本不兼容，可能需要修改一定的正则表达式
- 适用 CloudflareSpeedTest 版本：v2.2.5，先前版本未测试
- 脚本测试环境：debian12，其他 linux 发行版未测试

### 脚本工作流程：

1. 找到 mosdns 配置文件中带有 black_hole 和#tag::cloudflare_cdn_fastest_ip 的行
2. 检查此行中的 black_hole ip 是否需要更新
3. 如果需要更新，测试 Cloudflare CDN 最快 ip
4. 更新 black_hole ip
5. 重启 mosdns

### 使用方法：

1. 部署 [mosdns](https://github.com/IrineSistiana/mosdns)
2. 部署 [CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)
3. 根据根目录下的配置文件default.config修改配置
   ipset_ipv4_file：CloudflareSpeedTest项目中的ip.txt文件路径
   ipset_ipv6_file：CloudflareSpeedTest项目中的ipv6.txt文件路径
   cloudflare_speed_test_cmd：CloudflareSpeedTest项目中CloudflareST可执行文件路径
   mosdns_config_file：mosdns项目中的配置文件路径
   restart_mosdns_cmd：重启mosdns的命令
   log_fileb：日志文件路径
4. 编写 mosdns 配置文件，写法参考https://github.com/XIU2/CloudflareSpeedTest/discussions/317#discussioncomment-5824217
5. 为 mosdns 配置文件中的 exec：black_hole 这一行的末尾加上#tag::cloudflare_cdn_fastest_ip 的注释
6. 执行脚本。需要定时任务可自行编写 crontab 或 systemd 的 timer
