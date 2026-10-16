# BTIR-Client

BTIR 项目的桌面客户端，基于 Electron 打包。前端资源随安装包本地分发，通过远程 API 访问服务端，默认连接 <https://btir-online.ai-premol.cn/>。

# 环境要求

- Node.js ≥ 18
- 服务端需在 `BTIR_CORS_ORIGINS` 中放行 `app://btir`

## 快速开始

```bash
npm install # 安装依赖（国内网络可加：ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/）
npm start # 开发模式启动，直接读取 renderer/ 下的前端源码
```

## 与服务端对齐

主仓库更新前端后：

```bash
npm run sync # 从 BITR 主仓库的 frontend/ 同步 到 renderer/
node electron/sync.js /path/to/repo # 或指定主仓库路径
```

注意：`sync` 会整体覆盖 `renderer/frontend` 与 `renderer/assets`，同步后请用 `git diff` 检查再提交。

## 打包

```bash
npm run dist        # 按当前平台打包
npm run dist:win    # Windows NSIS 安装包
npm run dist:linux  # Linux AppImage
```

连接非默认服务端时：

```bash
BTIR_API_BASE=https://your-server.example.com npm start
```