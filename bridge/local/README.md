# 本机临时 Gateway

这套脚本使用仓库内参考项目的 `spider-gateway`，适合在没有 VPS 时先用本机联调 iPhone。

## 启动

在 PowerShell 中运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\ios-codex\bridge\local\start-gateway.ps1
```

脚本会自动生成 Token 并保存到 `bridge/local/state/gateway-token.txt`。启动后会显示本机局域网地址，例如：

```text
http://10.6.59.105:8787
```

iPhone 与电脑连接同一个 Wi-Fi 后，在丛丛影视设置中填写该地址和脚本显示的 Token。不要填写 `127.0.0.1`，那代表 iPhone 自己。

健康检查：

```powershell
.\ios-codex\bridge\local\health.ps1
```

## 当前能力边界

- CatVod Node bundle、HTTP/CMS、JS 类型源可以通过本机服务联调。
- `csp_*` 源使用 Android `classes.dex`，必须额外配置 Android Worker；Windows JVM 不能直接执行它。
- Gateway 没有 Worker 时，健康检查中的 `workerConfigured` 为 `false`，对应站点会返回 `WORKER_UNAVAILABLE`，不会伪装成可用。
- 临时服务默认只建议在可信局域网使用，不要把 8787 端口直接暴露到公网。

## 端口无法访问时

允许 Windows 防火墙放行当前端口（需要管理员 PowerShell）：

```powershell
New-NetFirewallRule -DisplayName 'CongcongTV Local Gateway 8787' -Direction Inbound -Protocol TCP -LocalPort 8787 -Action Allow -Profile Private
```

停止 Gateway 后可以删除规则：

```powershell
Remove-NetFirewallRule -DisplayName 'CongcongTV Local Gateway 8787'
```
