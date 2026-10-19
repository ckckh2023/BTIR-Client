import { PageHeader } from '../components/PageHeader';
import { AppTheme } from '../common/AppTheme';
import { AuthService } from '../service/AuthService';
import { ApiError } from '../common/ApiError';
import { TokenManager } from '../common/HttpClient';
import { ApiConfig } from '../common/ApiConfig';
import { buffer } from '@kit.ArkTS';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct LoginPage {
  @State username: string = '';
  @State password: string = '';
  @State confirmPassword: string = '';
  @State isRegisterMode: boolean = false;
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State showApiConfig: boolean = false;
  @State apiBaseUrl: string = '';

  private authService: AuthService = new AuthService();

  aboutToAppear(): void {
    this.apiBaseUrl = ApiConfig.getInstance().baseUrl;
    if (TokenManager.getInstance().isLoggedIn()) {
      if (TokenManager.getInstance().mustChangePassword) {
        router.replaceUrl({ url: 'pages/ChangePasswordPage' });
      } else {
        router.replaceUrl({ url: 'pages/HomePage' });
      }
    }
  }

  async handleSubmit(): Promise<void> {
    if (this.isLoading) return;
    const username = this.username.trim();
    if (!username) {
      this.errorMessage = '请输入用户名';
      return;
    }
    if (username.length > 32) {
      this.errorMessage = '用户名长度应为 2 至 32 个字符';
      return;
    }
    const isAsciiOnly = /^[\x00-\x7F]+$/.test(username);
    if (isAsciiOnly && username.length < 3) {
      this.errorMessage = '纯英文或数字用户名至少 3 个字符';
      return;
    }
    if (!isAsciiOnly && username.length < 2) {
      this.errorMessage = '用户名长度应为 2 至 32 个字符';
      return;
    }
    if (!/^[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7afa-zA-Z0-9_-]+$/.test(username)) {
      this.errorMessage = '用户名仅支持字母、数字、下划线和连字符';
      return;
    }
    if (!this.password) {
      this.errorMessage = '请输入密码';
      return;
    }
    if (this.password.length < 6 || this.password.length > 72) {
      this.errorMessage = '密码长度应为 6 至 72 个字符';
      return;
    }
    const utf8ByteLength = buffer.from(this.password, 'utf-8').length;
    if (utf8ByteLength > 72) {
      this.errorMessage = '密码的 UTF-8 编码不能超过 72 字节';
      return;
    }
    if (this.isRegisterMode) {
      if (this.password !== this.confirmPassword) {
        this.errorMessage = '两次输入的密码不一致';
        return;
      }
    }

    this.isLoading = true;
    this.errorMessage = '';

    try {
      const response = this.isRegisterMode
        ? await this.authService.register(username, this.password)
        : await this.authService.login(username, this.password);
      if (response.must_change_password) {
        router.replaceUrl({ url: 'pages/ChangePasswordPage' });
      } else {
        router.replaceUrl({ url: 'pages/HomePage' });
      }
    } catch (error) {
      if (error instanceof ApiError) {
        if (error.isRateLimited()) {
          this.errorMessage = '请求过于频繁，请稍后再试';
        } else if (error.isServiceUnavailable()) {
          this.errorMessage = '服务暂时不可用，请稍后再试';
        } else if (!this.isRegisterMode && error.statusCode === 401) {
          this.errorMessage = '用户名或密码错误';
        } else {
          this.errorMessage = error.message;
        }
      } else {
        this.errorMessage = `登录失败: ${String(error)}`;
      }
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
    PageHeader({ title: '智瞳医脑', showBack: false, canLeave: !this.isLoading })
    Scroll() {
    Column() {
      Text(this.isRegisterMode ? '创建账号' : '账号登录').fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppTheme.primary).width('85%').margin({ bottom: 24 })

      Row() {
        Button('登录')
          .enabled(!this.isLoading)
          .width('50%')
          .height(AppTheme.buttonHeight)
          .fontSize(16)
          .backgroundColor(this.isRegisterMode ? AppTheme.disabled : AppTheme.primary)
          .fontColor(this.isRegisterMode ? AppTheme.secondary : AppTheme.surface)
          .borderRadius(AppTheme.buttonRadius)
          .onClick(() => {
            this.isRegisterMode = false;
            this.errorMessage = '';
          })
        Button('注册')
          .enabled(!this.isLoading)
          .width('50%')
          .height(AppTheme.buttonHeight)
          .fontSize(16)
          .backgroundColor(this.isRegisterMode ? AppTheme.primary : AppTheme.disabled)
          .fontColor(this.isRegisterMode ? AppTheme.surface : AppTheme.secondary)
          .borderRadius(AppTheme.buttonRadius)
          .onClick(() => {
            this.isRegisterMode = true;
            this.errorMessage = '';
          })
      }
      .width('85%')
      .margin({ bottom: 24 })

      // 输入表单
      Column() {
        TextInput({ placeholder: '请输入用户名' })
          .width('100%')
          .height(48)
          .fontSize(16)
          .backgroundColor(AppTheme.subtle)
          .borderRadius(AppTheme.buttonRadius)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.username = value;
            this.errorMessage = '';
          })
          .margin({ bottom: 16 })

        TextInput({ placeholder: '请输入密码' })
          .width('100%')
          .height(48)
          .fontSize(16)
          .type(InputType.Password)
          .backgroundColor(AppTheme.subtle)
          .borderRadius(AppTheme.buttonRadius)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.password = value;
            this.errorMessage = '';
          })
          .margin({ bottom: 8 })

        if (this.isRegisterMode) {
          TextInput({ placeholder: '确认密码' })
            .width('100%')
            .height(48)
            .fontSize(16)
            .type(InputType.Password)
            .backgroundColor(AppTheme.subtle)
            .borderRadius(AppTheme.buttonRadius)
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => {
              this.confirmPassword = value;
              this.errorMessage = '';
            })
            .margin({ top: 8 })
        }
      }
      .width('85%')

      // 错误提示
      if (this.errorMessage) {
        Row() {
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor(AppTheme.danger)
        }
        .width('85%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(AppTheme.dangerBackground)
        .borderRadius(AppTheme.buttonRadius)
        .margin({ top: 8, bottom: 8 })
      }

      // 登录按钮
      Button(this.isLoading ? '处理中...' : (this.isRegisterMode ? '注册并登录' : '登录'))
        .width('85%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(AppTheme.primary)
        .fontColor(AppTheme.surface)
        .borderRadius(AppTheme.buttonRadius)
        .enabled(!this.isLoading)
        .margin({ top: 16 })
        .onClick(() => {
          this.handleSubmit();
        })

      // API 配置入口
      Row() {
        Text('服务器地址')
          .fontSize(12)
          .fontColor(AppTheme.muted)
          .onClick(() => {
            this.showApiConfig = !this.showApiConfig;
          })

        if (this.showApiConfig) {
          TextInput({ text: this.apiBaseUrl, placeholder: 'API Base URL' })
            .width('60%')
            .height(AppTheme.buttonHeight)
            .fontSize(12)
            .backgroundColor(AppTheme.subtle)
            .borderRadius(4)
            .onChange((value: string) => {
              this.apiBaseUrl = value;
            })

          Button('保存')
            .enabled(!this.isLoading)
            .height(AppTheme.buttonHeight)
            .fontSize(12)
            .backgroundColor(AppTheme.primary)
            .fontColor(AppTheme.surface)
            .borderRadius(4)
            .onClick(() => {
              try {
                if (ApiConfig.getInstance().setBaseUrl(this.apiBaseUrl)) TokenManager.getInstance().clearAuth();
                this.apiBaseUrl = ApiConfig.getInstance().baseUrl;
                this.errorMessage = '';
                this.showApiConfig = false;
              } catch (error) {
                this.errorMessage = (error as Error).message;
              }
            })
        }
      }
      .width('85%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 24 })
    }
    .width('92%').padding({ top: 28, bottom: 28 }).backgroundColor(AppTheme.surface).borderRadius(AppTheme.cardRadius)
    .border({ width: 1, color: AppTheme.border }).margin({ top: 24, bottom: 24 })
    }
    .width('100%')
    .layoutWeight(1).align(Alignment.Top)
    .scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(AppTheme.background)
  }
}
