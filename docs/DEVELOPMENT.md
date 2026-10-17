# 鸿蒙客户端开发

本文面向开发者。安装客户端和日常使用请阅读 [用户说明](../README.md)。

## 构建

安装 HarmonyOS 命令行工具、配套 SDK 和 JDK 21，将 `java`、`keytool`、`hvigorw` 与 `hdc` 加入 PATH 后，在项目根目录执行：

```bash
hvigorw assembleHap -p module=entry@default -p product=default --no-daemon --error
```

默认构建产物为 `entry/build/default/outputs/default/entry-default-unsigned.hap`。真机测试需要签名，参见 [签名与真机测试](HARMONYOS-SIGNING.md)。应用包名为 `cn.btir.client`。

## 本地 Linux 模拟器

`tools/btir-phone` 用于已经配置好的 Linux 开发环境：需要安装模拟器，准备 `BTIR_Phone` 实例和系统镜像，并使用用户级 systemd 服务管理上传转发进程。它不是用户安装客户端的前置步骤。

在项目根目录执行：

```bash
bash tools/btir-phone start
bash tools/btir-phone status
bash tools/btir-phone stop
```

`start` 启动模拟器和上传转发服务，然后启动已经安装的 BTIR。首次运行或更新构建后，可在模拟器连接成功时安装 HAP：

```bash
hdc -t 127.0.0.1:5555 install entry/build/default/outputs/default/entry-default-unsigned.hap
hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b cn.btir.client
```

首次尚未安装应用时，启动脚本可能报告应用启动失败；完成上述安装后可重新运行启动命令。

## 模拟器上传转发

模拟器使用默认服务端时，上传经 `10.0.2.2:18766` 访问主机的转发服务，由主机通过 HTTPS 发送到服务端。该服务只监听主机回环地址；真机不使用这条转发路径。

ZIP 和四模态 NIfTI 上传共用转发流程。为规避模拟器原生 multipart 上传损坏文件末尾的问题，客户端按 1 MiB 分块发送，由转发服务流式组装表单，最多缓存 4 MiB 分块。转发服务不保存病例文件，日志只记录上传路径、字节数和 HTTP 状态码。

上传转发失败时，先检查 `bash tools/btir-phone status`，再查看服务日志：

```bash
journalctl --user -u btir-emulator-upload-bridge.service
```

## 签名材料与测试包

密钥、证书与 Profile 放在已被 Git 忽略的 `.signing/` 目录。签名助手通过终端交互读取密码。不要将 P12、密码或含设备授权信息的调试 Profile 提交到仓库。

签名验证与目标手机安装验证需要分别完成；发布 Release 时请说明测试包适用设备及有效期。
