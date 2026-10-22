(function () {
    const form = document.getElementById('settingForm')
    const submitBtn = document.getElementById('submitBtn')
    const messageBox = document.getElementById('message')
    const input = document.getElementById('apiBase')
    const defaultHint = document.getElementById('defaultHint')
    const defaultBaseText = document.getElementById('defaultBaseText')
    const resetDefault = document.getElementById('resetDefault')
    const backLink = document.getElementById('backLink')
    const desktopOnly = document.getElementById('desktopOnly')
    const themeButton = document.getElementById('themeToggle')

    const showMessage = (text, type) => {
        messageBox.textContent = text
        messageBox.className = `message ${type}`
        messageBox.style.display = 'block'
    }
    const hideMessage = () => {
        messageBox.style.display = 'none'
    }

    const applyTheme = (theme) => {
        document.documentElement.setAttribute('data-theme', theme)
        document.querySelector('.guide-icon-dark').style.display = theme === 'dark' ? '' : 'none'
        document.querySelector('.guide-icon-light').style.display = theme === 'dark' ? 'none' : ''
    }
    themeButton.addEventListener('click', () => {
        const next = document.documentElement.getAttribute('data-theme') === 'dark'
            ? 'light'
            : 'dark'
        localStorage.setItem('btir_theme', next)
        applyTheme(next)
    })
    applyTheme(localStorage.getItem('btir_theme') || 'light')

    if (!window.btirEnv) {
        form.style.display = 'none'
        defaultHint.style.display = 'none'
        desktopOnly.style.display = 'block'
        return
    }

    const defaultBase = window.btirEnv.defaultApiBase || 'https://btir-online.ai-premol.cn'
    defaultBaseText.textContent = defaultBase

    input.value = window.btirEnv.apiBase || defaultBase
    input.focus()
    input.select()

    resetDefault.addEventListener('click', (event) => {
        event.preventDefault()
        input.value = defaultBase
        hideMessage()
        input.focus()
    })

    if (localStorage.getItem('btir_token')) {
        backLink.textContent = '返回主页'
        backLink.href = './index.html'
    }

    form.addEventListener('submit', async (event) => {
        event.preventDefault()
        hideMessage()

        const raw = input.value.trim().replace(/\/+$/, '')
        if (!raw) {
            showMessage('请输入服务源地址', 'error')
            return
        }
        let parsed
        try {
            parsed = new URL(raw)
        } catch {
            showMessage('服务源地址格式无效', 'error')
            return
        }
        if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
            showMessage('服务源地址必须以 http:// 或 https:// 开头', 'error')
            return
        }

        submitBtn.disabled = true
        submitBtn.textContent = '保存中...'
        try {
            if (raw === defaultBase) {
                localStorage.removeItem('btir_api_base')
            } else {
                localStorage.setItem('btir_api_base', raw)
            }
            localStorage.removeItem('btir_token')
            localStorage.removeItem('btir_user')
            showMessage('服务源已更新，正在前往登录页...', 'success')
            setTimeout(() => {
                window.location.href = './login.html'
            }, 600)
        } catch (err) {
            showMessage(`保存失败：${err.message || '请稍后重试'}`, 'error')
            submitBtn.disabled = false
            submitBtn.textContent = '保存并重新登录'
        }
    })
})()
