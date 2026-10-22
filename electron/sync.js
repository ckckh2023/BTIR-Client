const fs = require('node:fs')
const path = require('node:path')
const os = require('node:os')
const { spawn } = require('node:child_process')
const { parseArgs } = require('node:util')

const defaultClientRoot = path.resolve(__dirname, '..')
const upstreamRepository = 'https://github.com/ckckh2023/BTIR-BrainTumor-ImageRecognition.git'
const upstreamRef = 'main'

function findSourceRoot(clientRoot, requested) {
    if (!requested) throw new Error('本地同步必须显式指定主仓库路径')
    const source = path.resolve(requested)
    if (!['frontend', 'assets'].every(name => fs.existsSync(path.join(source, name)))) {
        throw new Error('未找到服务端 frontend 和 assets，请指定主仓库路径')
    }
    if (source === path.resolve(clientRoot)) throw new Error('服务端源目录不能是客户端目录')
    return source
}

function replaceOnce(text, pattern, replacement, label) {
    const matches = text.match(new RegExp(pattern.source, `${pattern.flags.replace('g', '')}g`)) || []
    if (matches.length !== 1) throw new Error(`桌面适配位置已变化：${label}`)
    return text.replace(pattern, replacement)
}

function adaptScripts(frontendRoot) {
    const apiBase = "(window.btirEnv && localStorage.getItem('btir_api_base')) || window.btirEnv?.apiBase || ''"
    for (const page of ['app', 'login']) {
        const file = path.join(frontendRoot, 'scripts', `${page}.js`)
        let text = fs.readFileSync(file, 'utf8')
        text = replaceOnce(text, /^([ \t]*)API_BASE: window\.btirEnv\?\.apiBase \?\? '',$/m,
            (_, indent) => `${indent}API_BASE: ${apiBase},\n${indent}isDesktop: !!window.btirEnv,`, `${page} API_BASE`)
        text = replaceOnce(text, /^([ \t]*)methods: \{$/m,
            (_, indent) => `${indent}methods: {\n${indent}    openSettings() {\n${indent}        window.location.href = 'setting.html'\n${indent}    },`, `${page} methods`)
        fs.writeFileSync(file, text)
    }
    const password = path.join(frontendRoot, 'scripts', 'change-password.js')
    fs.writeFileSync(password, replaceOnce(fs.readFileSync(password, 'utf8'), /window\.btirEnv\?\.apiBase \?\? ''/, apiBase, 'change-password API_BASE'))
}

function settingsButton(indent, icon) {
    return `${indent}<button v-if="isDesktop" type="button" class="desktop-settings-button btir-icon-button" title="服务源设置" aria-label="服务源设置" @click="openSettings">\n${indent}    ${icon.trim()}\n${indent}</button>\n`
}

function adaptPages(frontendRoot, icon) {
    for (const page of ['index', 'login']) {
        const file = path.join(frontendRoot, `${page}.html`)
        let html = fs.readFileSync(file, 'utf8')
        const marker = /^([ \t]*)<a class="client-download-entry btir-icon-button"[^>]*>[\s\S]*?<\/a>\n/m
        html = replaceOnce(html, marker, (_, indent) => settingsButton(indent, icon), `${page} 设置入口`)
        html = html.replace('auth-card-with-download-entry', 'auth-card-with-desktop-actions')
        html = replaceOnce(html, /<\/head>/, '    <link rel="stylesheet" href="./styles/desktop.css">\n</head>', `${page} 桌面样式`)
        fs.writeFileSync(file, html)
    }
}

function readDesktopFiles(rendererRoot) {
    const frontend = path.join(rendererRoot, 'frontend')
    const files = new Map()
    for (const name of ['setting.html', 'scripts/setting.js', 'styles/desktop.css']) {
        files.set(name, fs.readFileSync(path.join(frontend, name)))
    }
    const readme = path.join(frontend, 'README.md')
    if (fs.existsSync(readme)) files.set('README.md', fs.readFileSync(readme))
    const index = fs.readFileSync(path.join(frontend, 'index.html'), 'utf8')
    const icon = index.match(/@click="openSettings"[^>]*>\s*(<svg\b[\s\S]*?<\/svg>)\s*<\/button>/)
    if (!icon) throw new Error('现有桌面设置入口缺失，未执行同步')
    return { files, icon: icon[1] }
}

function syncRenderer(sourceRoot, clientRoot = defaultClientRoot) {
    const source = findSourceRoot(clientRoot, sourceRoot)
    const renderer = path.join(clientRoot, 'renderer')
    const desktop = readDesktopFiles(renderer)
    const workspace = fs.mkdtempSync(path.join(clientRoot, '.renderer-sync-'))
    const next = path.join(workspace, 'next')
    const previous = path.join(workspace, 'previous')
    let backedUp = false
    let installed = false
    let committed = false
    try {
        fs.cpSync(path.join(source, 'frontend'), path.join(next, 'frontend'), { recursive: true })
        fs.cpSync(path.join(source, 'assets'), path.join(next, 'assets'), { recursive: true })
        for (const [name, content] of desktop.files) {
            const target = path.join(next, 'frontend', name)
            fs.mkdirSync(path.dirname(target), { recursive: true })
            fs.writeFileSync(target, content)
        }
        for (const file of ['download.html', 'styles/download.css', 'scripts/download.js']) {
            fs.rmSync(path.join(next, 'frontend', file), { force: true })
        }
        adaptScripts(path.join(next, 'frontend'))
        adaptPages(path.join(next, 'frontend'), desktop.icon)
        const icon = path.join(next, 'assets', 'icon_exp.png')
        const stagedIcon = path.join(workspace, 'icon.png')
        const hasIcon = fs.existsSync(icon)
        if (hasIcon) {
            fs.mkdirSync(path.join(clientRoot, 'build'), { recursive: true })
            fs.copyFileSync(icon, stagedIcon)
        }
        if (fs.existsSync(renderer)) {
            fs.renameSync(renderer, previous)
            backedUp = true
        }
        fs.renameSync(next, renderer)
        installed = true
        if (hasIcon) fs.renameSync(stagedIcon, path.join(clientRoot, 'build', 'icon.png'))
        committed = true
        return renderer
    } catch (error) {
        if (backedUp) {
            if (installed) fs.renameSync(renderer, next)
            fs.renameSync(previous, renderer)
            backedUp = false
        }
        throw error
    } finally {
        // 恢复失败时保留备份，避免进一步删除原来的资源。
        if (committed || !backedUp) fs.rmSync(workspace, { recursive: true, force: true })
    }
}

function runGit(args, label = '') {
    return new Promise((resolve, reject) => {
        const started = Date.now()
        let output = '', errors = '', progress = '', frame = 0
        let timedOut = false, cancelled = false, finished = false
        const frames = ['-', '\\', '|', '/']
        const child = spawn('git', args, {
            stdio: ['ignore', 'pipe', 'pipe'],
            windowsHide: true,
            detached: process.platform !== 'win32',
            env: { ...process.env, GIT_TERMINAL_PROMPT: '0', LC_ALL: 'C' },
        })
        const stop = () => {
            if (!child.pid) return
            if (process.platform === 'win32') {
                const killer = spawn('taskkill', ['/pid', String(child.pid), '/T', '/F'], { stdio: 'ignore', windowsHide: true })
                killer.once('error', () => child.kill())
            } else {
                try { process.kill(-child.pid, 'SIGTERM') } catch { child.kill() }
            }
        }
        const render = () => {
            const elapsed = Math.floor((Date.now() - started) / 1000)
            process.stdout.write(`\r\x1b[2K${frames[frame++ % frames.length]} ${label}${progress}（${elapsed} 秒）`)
        }
        if (label) {
            if (process.stdout.isTTY) render()
            else console.log(label)
        }
        const animation = label && process.stdout.isTTY ? setInterval(render, 100) : null
        const timeout = setTimeout(() => { timedOut = true; stop() }, 120000)
        const interrupt = () => { cancelled = true; stop() }
        process.once('SIGINT', interrupt)
        child.stdout.on('data', chunk => { output += chunk })
        child.stderr.on('data', chunk => {
            const text = chunk.toString()
            errors = (errors + text).slice(-8192)
            const names = { 'Receiving objects': '接收', 'Resolving deltas': '整理', 'Updating files': '写入' }
            for (const match of text.matchAll(/(Receiving objects|Resolving deltas|Updating files):\s*(\d+)%/g)) {
                progress = ` · ${names[match[1]]} ${match[2]}%`
            }
        })
        const finish = (error, code) => {
            if (finished) return
            finished = true
            clearTimeout(timeout)
            clearInterval(animation)
            process.removeListener('SIGINT', interrupt)
            if (label && process.stdout.isTTY) process.stdout.write('\r\x1b[2K')
            if (error || code !== 0) {
                const message = timedOut ? 'GitHub 同步超时（120 秒），请检查网络连接后重试'
                    : cancelled ? '同步已取消'
                    : error?.code === 'ENOENT' ? '未找到 Git，请先安装 Git'
                    : `读取主仓库失败：${errors.trim() || error?.message || `Git 退出码 ${code}`}`
                const failure = new Error(message)
                if (cancelled) failure.code = 'SYNC_CANCELLED'
                reject(failure)
            } else {
                if (label && process.stdout.isTTY) console.log(`✓ ${label}`)
                resolve(output.trim())
            }
        }
        child.once('error', error => finish(error))
        child.once('close', code => finish(null, code))
    })
}

async function syncFromRemote(ref = upstreamRef, clientRoot = defaultClientRoot, repository = upstreamRepository) {
    if (!ref || ref.startsWith('-')) throw new Error('请指定有效的分支、标签或提交号')
    const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'btir-upstream-'))
    try {
        await runGit(['init', '--quiet', workspace])
        await runGit(['-C', workspace, 'remote', 'add', 'origin', repository])
        await runGit(['-C', workspace, 'fetch', '--progress', '--depth=1', '--filter=blob:none', '--no-tags', 'origin', ref], `正在获取远程版本 ${ref}`)
        const revision = await runGit(['-C', workspace, 'rev-parse', 'FETCH_HEAD'])
        const compatible = await runGit(['-C', workspace, 'ls-tree', '--name-only', 'FETCH_HEAD', '--', 'frontend/scripts/app.js'])
        if (!compatible) {
            throw new Error(`远程版本 ${ref}@${revision.slice(0, 12)} 尚未包含当前前端目录结构，请先提交主仓库的前端改动，或用 --ref 指定兼容版本`)
        }
        await runGit(['-C', workspace, 'checkout', '--progress', 'FETCH_HEAD', '--', 'frontend', 'assets'], '正在下载前端与资源')
        const target = syncRenderer(workspace, clientRoot)
        return { target, revision }
    } finally {
        fs.rmSync(workspace, { recursive: true, force: true })
    }
}

module.exports = { findSourceRoot, syncRenderer, syncFromRemote }

async function main() {
    try {
        const { values, positionals } = parseArgs({
            options: { ref: { type: 'string' } },
            allowPositionals: true,
        })
        if (positionals.length > 1 || (positionals.length && values.ref !== undefined)) {
            throw new Error('用法：node electron/sync.js [--ref 分支、标签或提交号]，或 node electron/sync.js 主仓库路径')
        }
        if (positionals.length) {
            const source = findSourceRoot(defaultClientRoot, positionals[0])
            const target = syncRenderer(source)
            console.log(`已从本地同步前端与资源：${source} → ${target}`)
        } else {
            const ref = values.ref ?? upstreamRef
            const { target, revision } = await syncFromRemote(ref)
            console.log(`已同步 ${upstreamRepository} ${ref}@${revision} → ${target}`)
        }
    } catch (error) {
        console.error(error.message)
        process.exitCode = error.code === 'SYNC_CANCELLED' ? 130 : 1
    }
}

if (require.main === module) main()
