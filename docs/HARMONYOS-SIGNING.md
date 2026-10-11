# 鸿蒙真机签名与安装

当前工程 `signingConfigs` 为空，默认构建的 `entry-default-unsigned.hap` 没有签名。它已在开发模拟器中测试，但不能作为华为真机安装包分发。SDK 官方 `hap-sign-tool.jar verify-app` 对当前产物报告 `signature not found`。

用户提供的视频是 HAP 手动签名教程。其主要步骤为：约 1 分钟生成 P12/CSR，3–8 分钟在 AppGallery Connect（AGC）申请证书、登记设备和 Profile，9–15 分钟配置签名材料并打包。以下流程适用于本项目的 Linux 命令行环境。

## 如何确认当前进度

截至本次检查，本机已安装 JDK 21、Hvigor、HDC 和官方签名工具；当前 HAP 未签名，常用下载目录及工程中未找到配套签名材料，HDC 未检测到设备。账号内的证书与 Profile 状态需要登录 AGC 确认。

| 检查位置 | 应确认的内容 |
| --- | --- |
| 本机签名材料 | 有 `.p12` 私钥库及对应的密钥别名和密码；只有 `.cer` 不够。 |
| AGC“证书” | 有有效的 HarmonyOS 调试证书，且由该 P12 的 CSR 申请。 |
| AGC“APP ID” | 有包名为 `cn.btir.client` 的 HarmonyOS 应用。 |
| AGC“设备”与“Profile” | 已登记目标手机 UDID；调试 Profile 关联上述应用、证书和手机。 |

如果没有这些材料，从步骤 1 开始；如果 AGC 已有证书但对应的 P12 丢失，不能只下载证书继续签名，需要用新密钥重新申请配套证书和 Profile。

## 1. 生成密钥和 CSR

如果已有与华为调试证书对应的密钥，请复用该密钥及别名。首次配置时，在项目根目录执行：

```bash
python3 tools/btir-sign prepare
```

终端会交互询问密码，生成 `.signing/btir-debug.p12` 和 `.signing/btir-debug.csr`，别名为 `btir-debug`，组织（O）为 `BTIR`。建议密码至少 8 位并包含大小写字母、数字或符号中的两种以上；导出 CSR 时再次输入同一密码。默认使用 EC P-256 与 SHA256withECDSA。可以通过 `--subject` 自定义 CSR 主体。

`.signing/` 已加入 Git 忽略列表。P12 和密码需要保留以便后续更新使用相同签名；申请证书时只上传 CSR。此步骤只生成本地密钥和请求，并未获得华为信任的应用证书。

如果之前生成的 CSR 组织字段不正确，复用原 P12 导出新请求：

```bash
python3 tools/btir-sign csr
```

输入原密钥库密码后，将生成 `.signing/btir-debug-btir.csr`，组织为 `BTIR`；申请证书时上传这个新文件。原密钥和旧 CSR 保留。若已用旧 CSR 申请证书，需要用新 CSR 重新申请证书，再生成配套 Profile。

## 2. 在 AGC 准备应用、证书和调试 Profile

登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)，进入“证书、APP ID和Profile”：

1. 创建或选择 HarmonyOS 应用，包名必须为 **`cn.btir.client`**。
2. 新增**调试证书**，上传刚生成的 CSR。下载证书，保存为 `.signing/btir-debug.cer`。
3. 给要测试的真机开启开发者模式和 USB 调试，连接电脑并在手机上授权调试。用 `hdc list targets` 查看设备标识，再获取该真机的 UDID：

   ```bash
   hdc -t <真机设备标识> shell bm get --udid
   ```

   如果模拟器也在线，必须明确指定真机，不能用模拟器 UDID 代替手机 UDID。
4. 在 AGC“设备”中登记目标真机的 UDID。
5. 新增 **调试 Profile**：选择 BTIR 应用、步骤 2 的调试证书以及步骤 4 的设备。下载为 `.signing/btir-debug.p7b`。

证书和 Profile 必须配套。新增测试手机时，要把它加入设备列表并重新生成包含该设备的 Profile，再重新签名。同一个调试 Profile 可以包含多个注册设备。

### 没有本地真机时

不需要把目标手机连接到这台电脑才能申请 Profile，但需要取得实际安装设备的 UDID。

用户提供的视频在约 5 分 05 秒的“01-5 选择设备”幻灯片中提供了比赛主办方的测试设备 UDID，要求参赛者登记该设备。该流程让主办方收到安装包后能在自己的手机上安装；本地没有手机的参赛者也可以完成这一步。如果用于该赛事提交，先向主办方确认当前测试设备 UDID，再在 AGC 中登记并加入调试 Profile。历史教程中的设备标识不保证仍适用于当前活动。

如果用于朋友或其他测试者的手机，请由对方获取其手机 UDID，再把它登记到自己的 AGC 并加入 Profile。对方可在其电脑上通过 `hdc shell bm get --udid` 获取；登记模拟器或别人的设备不能授权目标手机。

如果暂时没有任何可用测试手机，可考虑华为 AGC 的“质量 > 云调试”。云真机可用于远程验证，具体机型、账号权限和应用签名要求以当前服务页面为准。它不意味着生成的调试包能安装到所有用户手机。

## 3. 构建、签名和验证

先使用已配置的 Hvigor 构建最新 HAP：

```bash
hvigorw assembleHap -p module=entry@default -p product=default --no-daemon --error
python3 tools/btir-sign sign
```

签名助手使用本机 SDK 的官方签名工具，并通过 `-pwdInputMode 1` 在终端交互输入密码。生成 `.signing/BTIR-device-signed.hap`，随后执行 `verify-app` 检查签名及文件完整性。已有输出不会被覆盖，可以用 `--output` 指定新名称。密码不写入 `build-profile.json5`。

官方工具会先询问 `KeystorePwd`，再询问 `KeyPwd`，每次只有 30 秒输入时间。本助手生成的 P12 两次输入相同的原密码，按回车提交；不要留空，也不要将命令放入管道或重定向输出。超时或没有可用终端时，工具可能拿到空密码并报告 `keystore password was incorrect`。

如果报 `11014003 Init keystore failed`，可以先在终端单独检查原密码：

```bash
keytool -list -keystore .signing/btir-debug.p12 -alias btir-debug
```

输入正确密码后应显示该别名的条目，并且没有密码或完整性警告。这个检查不会修改 P12。若仍提示密码错误，先确认保存的是生成该 P12 时设置的密码；如果密码丢失，需要用新的密钥重新申请配套证书和 Profile，不能只修改现有 CSR。

复用已有材料时，可指定路径及真实密钥别名：

```bash
python3 tools/btir-sign sign \
  --keystore /absolute/path/developer.p12 \
  --certificate /absolute/path/debug.cer \
  --profile /absolute/path/debug.p7b \
  --alias your-key-alias \
  --output /absolute/path/BTIR-device-signed.hap
```

签名工具默认从这台机器的 `~/.local/share/harmonyos/command-line-tools/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar` 加载。其他环境可用 `BTIR_HAP_SIGN_TOOL` 指定完整路径；`java` 与 `keytool` 应使用 JDK 21。

## 4. 安装到已登记的真机

```bash
hdc -t <真机设备标识> install .signing/BTIR-device-signed.hap
hdc -t <真机设备标识> shell aa start -a EntryAbility -b cn.btir.client
```

当前项目最低兼容 HarmonyOS 5 / API 12。签名工具验证通过仅代表包内签名与完整性通过；真机还会验证证书信任、Profile 和 UDID。必须在目标手机上安装验证，才能确认实机可用。

使用调试证书与调试 Profile 进行开发测试。发布证书与发布 Profile 用于正式分发流程；希望让未登记 UDID 的用户安装时，应走 AGC 邀请测试/应用市场等适用的官方分发渠道，而不是继续发 unsigned HAP 或把自签名证书当作华为授权证书。

## 常见安装失败

| 错误/现象 | 检查项 |
| --- | --- |
| `signature not found` | 传入了 unsigned 包，或没有成功签名。 |
| `9568322` 来源不可信 | 检查是否用了发布 Profile，以及证书链与 Profile 是否受设备信任。 |
| 设备未授权 | 调试 Profile 必须包含当前真机 UDID。 |
| 包名不一致 | Profile 对应包名必须是 `cn.btir.client`。 |
| 签名不一致 | 真机已有同包名但使用另一签名的应用。先确认是否需要保留旧应用数据，再处理旧版本。 |
| 证书过期或手机系统过旧 | 检查 AGC 证书/Profile 有效期和手机 API 版本。 |

## 官方参考

- [自动签名](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-signing-auto)：有 Windows/macOS DevEco Studio 时，可连接真机后登录华为账号自动生成签名材料。
- [申请调试 Profile](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/agc-help-debug-profile-0000002248181278)：选择应用、调试证书及已注册设备。
- [获取 UDID](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-performance-analysis-kit-59)。
- [华为关于 `9568322` 的定位案例](https://developer.huawei.com/consumer/cn/forum/topic/0201174845503607516)：发布签名无法用于该案例的本地自测，应使用测试签名。
- 当前安装的官方 SDK `hap-sign-tool.jar -h`：本地生成、签名和验证的参数依据。
