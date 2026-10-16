const { contextBridge } = require('electron')

const DEFAULT_API_BASE = 'https://btir-online.ai-premol.cn'
const ENV_API_BASE = process.env.BTIR_API_BASE || ''

const readSavedApiBase = () => {
    try {
        return localStorage.getItem('btir_api_base') || null
    } catch {
        return null
    }
}

const savedApiBase = readSavedApiBase()

contextBridge.exposeInMainWorld('btirEnv', {
    apiBase: ENV_API_BASE || savedApiBase || DEFAULT_API_BASE,
    defaultApiBase: DEFAULT_API_BASE,
})