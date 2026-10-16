const { app, BrowserWindow, Menu, protocol, net, shell } = require('electron')
const path = require('node:path')
const { pathToFileURL } = require('node:url')

const APP_SCHEME = 'app'
const APP_HOST = 'btir'


protocol.registerSchemesAsPrivileged([
    {
        scheme: APP_SCHEME,
        privileges: {
            standard: true,
            secure: true,
            supportFetchAPI: true,
            stream: true,
        },
    },
])

const rendererRoot = app.isPackaged
    ? path.join(process.resourcesPath, 'renderer')
    : path.join(__dirname, '..', 'renderer')

const frontendRoot = path.join(rendererRoot, 'frontend')
const assetsRoot = path.join(rendererRoot, 'assets')

const resolveWithin = (baseDir, relativePath) => {
    const target = path.resolve(baseDir, `.${path.sep}${relativePath}`)
    if (target !== baseDir && !target.startsWith(baseDir + path.sep)) return null
    return target
}

const handleAppRequest = (request) => {
    const url = new URL(request.url)
    if (url.hostname !== APP_HOST) {
        return new Response('Not Found', { status: 404 })
    }
    const isAsset = url.pathname.startsWith('/assets/')
    const relativePath = isAsset
        ? url.pathname.slice('/assets/'.length)
        : url.pathname === '/' ? 'index.html' : url.pathname.slice(1)
    const baseDir = isAsset ? assetsRoot : frontendRoot
    const filePath = resolveWithin(baseDir, decodeURIComponent(relativePath))
    if (!filePath) {
        return new Response('Forbidden', { status: 403 })
    }
    return net.fetch(pathToFileURL(filePath).href)
}

const createMainWindow = () => {
    const win = new BrowserWindow({
        width: 1366,
        height: 860,
        minWidth: 1024,
        minHeight: 700,
        icon: path.join(assetsRoot, 'icon_exp.png'),
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false,
            sandbox: true,
        },
    })
    win.webContents.setWindowOpenHandler(({ url }) => {
        if (url === 'about:blank') return { action: 'allow' }
        shell.openExternal(url)
        return { action: 'deny' }
    })
    win.webContents.on('before-input-event', (event, input) => {
        if (input.type !== 'keyDown') return
        const key = (input.key || '').toLowerCase()
        if (input.control && key === 'r') {
            win.webContents.reload()
            event.preventDefault()
        } else if (!app.isPackaged && (key === 'f12' || (input.control && input.shift && key === 'i'))) {
            win.webContents.toggleDevTools()
            event.preventDefault()
        }
    })
    win.loadURL(`${APP_SCHEME}://${APP_HOST}/index.html`)
    return win
}

const gotLock = app.requestSingleInstanceLock()

if (!gotLock) {
    app.quit()
} else {
    app.on('second-instance', () => {
        const [win] = BrowserWindow.getAllWindows()
        if (win) {
            if (win.isMinimized()) win.restore()
            win.focus()
        }
    })

    app.whenReady().then(() => {
        Menu.setApplicationMenu(null)
        protocol.handle(APP_SCHEME, handleAppRequest)
        createMainWindow()
        app.on('activate', () => {
            if (BrowserWindow.getAllWindows().length === 0) createMainWindow()
        })
    })

    app.on('window-all-closed', () => {
        if (process.platform !== 'darwin') app.quit()
    })
}