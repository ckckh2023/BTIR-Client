# BTIR-Client
BTIR 项目的客户端版本，可与服务端对齐，为网页版使用扩展更多场景。

服务端相关内容在 https://github.com/ckckh2023/BTIR-BrainTumor-ImageRecognition

## 鸿蒙模拟器

在这台 Linux 开发机上运行 `btir-phone start` 可启动模拟器、BTIR 应用和本机上传转发服务；用 `btir-phone status` 检查状态，`btir-phone stop` 停止。真机无需本机转发服务。

模拟器上传使用 `10.0.2.2` 将数据交给只监听电脑本地地址的转发服务，电脑再通过 HTTPS 发送到正式服务端。由于模拟器原生 multipart 上传会破坏文件末尾，应用将文件按 1 MiB 分块发送，由转发服务流式组装表单。转发服务最多缓存 4 MiB 分块，不保存病例文件；日志只记录上传路径、字节数和 HTTP 状态码。
