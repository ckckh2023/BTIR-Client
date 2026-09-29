import { AuthService } from '../service/AuthService';
import { ApiError } from '../common/ApiError';
import { TokenManager } from '../common/HttpClient';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct LoginPage {
  @State username: string = '';
  @State password: string = '';
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State showApiConfig: boolean = false;
  @State apiBaseUrl: string = '';

  private authService: AuthService = new AuthService();

  aboutToAppear(): void {
    this.apiBaseUrl = AppStorage.get<string>('api_base_url') ?? 'https://btir-online.ai-premol.cn';
    if (TokenManager.getInstance().isLoggedIn()) {
      if (TokenManager.getInstance().mustChangePassword) {
        router.replaceUrl({ url: 'pages/ChangePasswordPage' });
      } else {
        router.replaceUrl({ url: 'pages/HomePage' });
      }
    }
  }

  async handleLogin(): Promise<void> {
    if (!this.username || !this.password) {
      this.errorMessage = '请输入用户名和密码';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';

    try {
      const response = await this.authService.login(this.username, this.password);
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
        } else if (error.statusCode === 401) {
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
      // 顶部 Logo 区域
      Column() {
        Text('智瞳医脑')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A73E8')
          .margin({ top: 80 })

        Text('脑肿瘤MRI影像智能辅助诊断')
          .fontSize(14)
          .fontColor('#666666')
          .margin({ top: 8 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 40 })

      // 输入表单
      Column() {
        TextInput({ placeholder: '用户名' })
          .width('100%')
          .height(48)
          .fontSize(16)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.username = value;
            this.errorMessage = '';
          })
          .margin({ bottom: 16 })

        TextInput({ placeholder: '密码' })
          .width('100%')
          .height(48)
          .fontSize(16)
          .type(InputType.Password)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.password = value;
            this.errorMessage = '';
          })
          .margin({ bottom: 8 })
      }
      .width('85%')
      .padding({ left: 20, right: 20 })

      // 错误提示
      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor('#E53935')
          .margin({ top: 8, bottom: 8 })
          .width('85%')
      }

      // 登录按钮
      Button(this.isLoading ? '登录中...' : '登录')
        .width('85%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .backgroundColor('#1A73E8')
        .borderRadius(8)
        .enabled(!this.isLoading)
        .margin({ top: 16 })
        .onClick(() => {
          this.handleLogin();
        })

      // API 配置入口
      Row() {
        Text('服务器地址')
          .fontSize(12)
          .fontColor('#999999')
          .onClick(() => {
            this.showApiConfig = !this.showApiConfig;
          })

        if (this.showApiConfig) {
          TextInput({ text: this.apiBaseUrl, placeholder: 'API Base URL' })
            .width('60%')
            .height(36)
            .fontSize(12)
            .backgroundColor('#F5F5F5')
            .borderRadius(4)
            .onChange((value: string) => {
              this.apiBaseUrl = value;
            })

          Button('保存')
            .height(36)
            .fontSize(12)
            .backgroundColor('#1A73E8')
            .onClick(() => {
              AppStorage.setOrCreate<string>('api_base_url', this.apiBaseUrl.replace(/\/+$/, ''));
              this.showApiConfig = false;
            })
        }
      }
      .width('85%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
