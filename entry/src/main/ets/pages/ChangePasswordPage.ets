import { AuthService } from '../service/AuthService';
import { ApiError } from '../common/ApiError';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct ChangePasswordPage {
  @State currentPassword: string = '';
  @State newPassword: string = '';
  @State confirmPassword: string = '';
  @State isLoading: boolean = false;
  @State errorMessage: string = '';

  private authService: AuthService = new AuthService();

  async handleChangePassword(): Promise<void> {
    if (!this.currentPassword || !this.newPassword) {
      this.errorMessage = '请填写所有字段';
      return;
    }

    if (this.newPassword.length < 6) {
      this.errorMessage = '新密码长度至少6个字符';
      return;
    }

    if (this.newPassword !== this.confirmPassword) {
      this.errorMessage = '两次输入的新密码不一致';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';

    try {
      await this.authService.changePassword(this.currentPassword, this.newPassword);
      router.replaceUrl({ url: 'pages/HomePage' });
    } catch (error) {
      if (error instanceof ApiError) {
        if (error.statusCode === 401) {
          this.errorMessage = '当前密码错误';
        } else if (error.statusCode === 403) {
          this.errorMessage = '账号已被禁用，请联系管理员';
        } else {
          this.errorMessage = error.message;
        }
      } else {
        this.errorMessage = `修改密码失败: ${String(error)}`;
      }
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      // 标题区域
      Column() {
        Text('修改密码')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ top: 60 })

        Text('首次登录需要修改临时密码')
          .fontSize(14)
          .fontColor('#666666')
          .margin({ top: 8 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 40 })

      // 输入表单
      Column() {
        TextInput({ placeholder: '当前密码（临时密码）' })
          .width('100%')
          .height(48)
          .fontSize(16)
          .type(InputType.Password)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.currentPassword = value;
            this.errorMessage = '';
          })
          .margin({ bottom: 16 })

        TextInput({ placeholder: '新密码（至少6个字符）' })
          .width('100%')
          .height(48)
          .fontSize(16)
          .type(InputType.Password)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.newPassword = value;
            this.errorMessage = '';
          })
          .margin({ bottom: 16 })

        TextInput({ placeholder: '确认新密码' })
          .width('100%')
          .height(48)
          .fontSize(16)
          .type(InputType.Password)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.confirmPassword = value;
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

      // 修改密码按钮
      Button(this.isLoading ? '提交中...' : '修改密码')
        .width('85%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .backgroundColor('#1A73E8')
        .borderRadius(8)
        .enabled(!this.isLoading)
        .margin({ top: 16 })
        .onClick(() => {
          this.handleChangePassword();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
