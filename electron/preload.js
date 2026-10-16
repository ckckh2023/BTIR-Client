const { contextBridge } = require('electron')

const API_BASE = process.env.BTIR_API_BASE || 'https://btir-online.ai-premol.cn'

contextBridge.exposeInMainWorld('btirEnv', {
    apiBase: API_BASE,
})