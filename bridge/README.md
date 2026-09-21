# 丛丛影视 Bridge 说明

当前配置的 45 个 `csp_*` 源使用 Android `spider2.jar`，iOS 不能直接执行。推荐使用现成的：

```text
https://github.com/shareu007/tvbox-Swift-macOS/tree/main/spider-gateway
```

它的 `/v1/spider/invoke` 协议已经被 `lib/main.dart` 支持。Gateway 负责下载和缓存 JAR，Android Worker 负责通过 `DexClassLoader` 执行 DEX。

## Gateway 端

```bash
git clone https://github.com/shareu007/tvbox-Swift-macOS.git
cd tvbox-Swift-macOS/spider-gateway
export SPIDER_GATEWAY_HOST=0.0.0.0
export SPIDER_GATEWAY_PORT=8787
export SPIDER_GATEWAY_TOKEN='请替换为至少 32 位随机字符串'
export SPIDER_JAR_ALLOWED_HOSTS='gh.xxooo.cf'
npm start
```

正式部署必须使用 HTTPS 反向代理，并设置 Token。Gateway 只负责协议和调度；没有 Android Worker 时，JAR 请求会失败，这是预期行为。

## Android Worker 端

Worker 需要实现 Gateway README 中的一行一 JSON 协议：

- `init`：接收 `jarPath`、`jarDigest` 和站点信息。
- `invoke`：接收 `home`、`category`、`detail`、`search`、`player` 动作。
- `home` 合并 `homeContent` 与 `homeVideoContent`。
- 类名为 `com.github.catvod.spider.<api 去掉 csp_>`。
- 普通日志不能写入 stdout，只能写 stderr。

这部分必须运行在 Android ART 环境中，不能用 Windows JVM 或 iOS JavaScriptCore 代替。你提供的 `D:\Desktop\AIcode\movie` 可用于继续制作/验证 Worker，但其中的普通 JVM 兼容 JAR 不是原始 DEX 的等价运行时。

## App 端

在丛丛影视设置页填写：

- Gateway 地址：`https://你的域名`
- Gateway Token：与 `SPIDER_GATEWAY_TOKEN` 相同

App 会把原配置里每个站点的 `key`、`api`、`jar`、`ext` 原样提交给 Gateway，因此不需要修改原始配置链接。

## StreamBox 兼容模式

`huangj17/StreamBox-APP` 的 `jar-bridge` 暴露 `/api/{key}` CMS 接口，App 也会在 `/v1/spider/invoke` 失败后尝试该接口。它要求标准 JVM class JAR；当前 `spider2.jar` 内含 `classes.dex`，不能直接使用。
