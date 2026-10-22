# BTIR-Client

BTIR 项目的桌面客户端，基于 Electron 打包。前端资源随应用本地分发，通过远程 API 访问服务端，默认连接 <https://btir-online.ai-premol.cn/>。

# 环境要求

- Node.js ≥ 18
- Git
- 桌面运行时为 Electron 34.5.8
- 服务端需在 `BTIR_CORS_ORIGINS` 中放行 `app://btir`

## 快速开始

```bash
npm install # 安装依赖（国内网络可加：ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/）
npm start # 开发模式启动，直接读取 renderer/ 下的前端源码
```

## 与服务端对齐

主仓库更新前端后：

```bash
npm run sync # 从 GitHub 主仓库 main 分支同步前端与资源
npm run sync -- --ref main # 可改为团队指定的分支、标签或提交号
node electron/sync.js /path/to/repo # 仅本地联调时显式指定路径
```

注意：默认同步只读取 GitHub 已提交的内容，并输出提交号；保留桌面设置并自动适配客户端。同步后请用 `git diff` 检查再提交。

## 打包

```bash
npm run dist # 按当前平台打包
npm run dist:win # Windows
npm run dist:linux # Linux
npm run dist:harmony # 鸿蒙 PC
```

Windows、Linux 默认产物为绿色免安装目录。

Windows 可以使用 `npx electron-builder --win nsis --x64 --publish never` 生成安装包。

Linux 可以使用 `npx electron-builder --linux AppImage deb` 进行 AppImage 和 Deb 包的产出。

连接非默认服务端时：

```bash
BTIR_API_BASE=https://your-server.example.com npm start
```
