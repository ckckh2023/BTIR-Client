const fs = require('node:fs')
const path = require('node:path')

const clientRoot = path.join(__dirname, '..')
const sourceRoot = process.argv[2]
    ? path.resolve(process.argv[2])
    : path.join(clientRoot, '..', 'BTIR-BrainTumor-ImageRecognition')
const rendererRoot = path.join(clientRoot, 'renderer')
const buildRoot = path.join(clientRoot, 'build')

if (!fs.existsSync(path.join(sourceRoot, 'frontend'))) {
    console.error(`未找到前端源码目录: ${path.join(sourceRoot, 'frontend')}`)
    console.error('用法: node electron/sync.js [主仓库路径]')
    process.exit(1)
}

fs.rmSync(path.join(rendererRoot, 'frontend'), { recursive: true, force: true })
fs.cpSync(path.join(sourceRoot, 'frontend'), path.join(rendererRoot, 'frontend'), { recursive: true })
fs.rmSync(path.join(rendererRoot, 'assets'), { recursive: true, force: true })
fs.cpSync(path.join(sourceRoot, 'assets'), path.join(rendererRoot, 'assets'), { recursive: true })

fs.mkdirSync(buildRoot, { recursive: true })
const iconSource = path.join(rendererRoot, 'assets', 'icon_exp.png')
const iconTarget = path.join(buildRoot, 'icon.png')
if (fs.existsSync(iconSource)) {
    fs.copyFileSync(iconSource, iconTarget)
}

console.log(`已从 ${sourceRoot} 同步 frontend 与 assets 到 ${rendererRoot}`)