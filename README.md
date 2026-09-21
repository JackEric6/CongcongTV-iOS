# 丛丛影视 iOS（Flutter）

这是一个独立的 Flutter iOS 工程，所有本次产出都放在 `ios-codex` 目录。应用默认使用你提供的配置：

```text
https://ghproxy.net/https://raw.githubusercontent.com/JackEric6/movie/refs/heads/main/movie2
```

## 已实现

- Flutter + Dart 主界面，支持 iPhone 竖屏和横屏。
- 读取、缓存和替换 TVBox 配置；保留原配置的 `sites`、`urls`、顶层 `spider` 和对象型 `ext`。
- 普通 HTTP/CMS 源：分类、搜索、详情、选集和 HLS/MP4 播放。
- `type=3` 且 `api` 是 HTTP/HTTPS `.js`：通过 iOS JavaScriptCore 执行 drpy2，复用原有 `JSEnv.bundle.js` 和依赖资源。
- `csp_*` Android Spider：通过可选的外部 JAR Bridge/Spider Gateway 执行，iOS 本身不执行 DEX。
- GitHub Actions 在 macOS runner 上生成未签名 IPA，Windows 不需要 Mac。

## 当前配置的真实情况

截至 2026 年 9 月 21 日，配置在线返回 48 个站点：3 个 HTTP/JS 类型源，45 个 `csp_*` 源；顶层 `spider` 指向 `spider2.jar`，文件内部是 Android `classes.dex`。

Flutter 不会改变这个运行时边界。Android DEX 不能直接放进 iOS IPA 执行，所以应用会：

1. 直接执行 3 个可执行的 HTTP/JS 源。
2. 对 45 个 `csp_*` 源优先调用 `/v1/spider/invoke` Gateway。
3. 如果 Gateway 不可用，再尝试兼容 StreamBox 风格的 `/api/{key}` CMS Bridge。
4. 没有 Bridge 时明确提示“此 Android spider 需要配置 JAR Bridge 地址”，不会假装站点可用。

## Bridge 方案

### 推荐：Android Worker Gateway

参考 `shareu007/tvbox-Swift-macOS` 的 `spider-gateway`：

- Gateway 是 Node.js 服务，提供 `/v1/spider/invoke`。
- Gateway 接收配置里的 `jar`、`api`、`ext` 和调用动作。
- Android Worker 通过 `DexClassLoader` 加载 `com.github.catvod.spider.<api 去掉 csp_>`，执行 `homeContent`、`categoryContent`、`detailContent`、`searchContent` 和 `playerContent`。
- iOS 只通过 HTTPS 请求 Gateway，不接触 Android DEX。

该方案需要单独部署 Android Worker。只有启动 Node Gateway、没有 Worker 时，`csp_*` 调用仍会返回 `WORKER_UNAVAILABLE`。

### 备选：StreamBox JAR Bridge

`huangj17/StreamBox-APP` 的 `jar-bridge` 提供 `/api/{key}` CMS 兼容接口，但它要求插件已经是标准 JVM class JAR，并且入口类可被 `URLClassLoader` 加载。当前 `spider2.jar` 是 DEX，不能直接放进这个 Bridge；即使使用 dex2jar 转换，也要验证 Android API、JNI 和保护运行时依赖是否已经被替代。

## App 中配置 Bridge

打开 App 的设置页，填写：

- `JAR Bridge / Spider Gateway 地址`：例如 `https://gateway.example.com`
- `Gateway Token`：与服务端的 Bearer Token 一致；本地测试可留空

配置链接仍然使用上面的原始地址，不需要改写 48 个站点。

## 没有 Mac：生成 IPA

1. 在 GitHub 新建一个 Private 仓库，把 `ios-codex` 内的工程文件上传到仓库根目录；不要上传 `.research-*` 和 `.toolcache`。
2. 打开 `Actions`，选择 `Build unsigned Flutter iOS IPA`。
3. 点击 `Run workflow`，等待 macOS runner 完成 Flutter 构建。
4. 在构建结果的 Artifacts 下载 `CongcongTV-unsigned-ipa.zip`，解压得到 `CongcongTV-unsigned.ipa`。

工作流只编译应用，不保存 Apple ID、证书或密码。当前 Windows 无法本地运行 Xcode，因此 IPA 必须通过 GitHub Actions 或其他 macOS 构建机生成。

## AltStore 安装

1. 在 Windows 安装 AltServer，并按 AltServer 要求安装 Apple 的 iTunes/iCloud 组件。
2. 用数据线连接 iPhone，点“信任此电脑”，按 AltServer 流程先安装 AltStore。
3. 把 `CongcongTV-unsigned.ipa` 放到 iPhone“文件”App，使用“共享 -> AltStore”，或在 AltStore 的应用页用 `+` 导入。
4. 按提示输入自己的 Apple ID。密码只输入官方 AltServer/AltStore 界面，不要写入工程或发给任何人。
5. 首次打开若提示不受信任，到“设置 -> 通用 -> VPN 与设备管理”信任对应开发者。

免费 Apple ID 的侧载签名有效期通常较短，需要在 AltStore/AltServer 中定期刷新；付费开发者账号的签名周期和限制以 Apple 当前规则为准。

## SideStore 安装

1. 在 Windows 使用 SideStore 官方安装流程或 iLoader，把 SideStore 安装到 iPhone。
2. 在手机上完成 SideStore 的 LocalDevVPN/配对设置。
3. 将 IPA 放到“文件”App，通过“共享 -> SideStore”导入，或者在 SideStore 中选择 IPA。
4. 后续在 SideStore 内刷新应用签名。

## 目录

```text
ios-codex/
├── lib/main.dart                 # Flutter UI、配置解析、CMS/Spider Gateway 客户端
├── assets/js/                    # 现有 drpy2 与 JSEnv 资源
├── native_ios/                   # Flutter iOS 宿主的 JavaScriptCore 桥接
├── pubspec.yaml
├── .github/workflows/            # macOS runner 未签名 IPA 构建
├── bridge/README.md              # Android Worker/Gateway 部署说明
└── CongcongTV/                   # 原生参考实现与资源备份
```

## 本地 Flutter 构建（可选）

在 macOS 或已安装 Flutter 的机器上：

```bash
flutter create --platforms=ios --org com.congcong --project-name congcongtv .
cp native_ios/AppDelegate.swift ios/Runner/AppDelegate.swift
cp native_ios/IOSSpiderRunner.swift ios/Runner/IOSSpiderRunner.swift
flutter pub get
flutter build ios --release --no-codesign
```

之后需要用自己的 Apple Developer 签名，或将生成的未签名 IPA 交给 AltStore/SideStore 重新签名。
