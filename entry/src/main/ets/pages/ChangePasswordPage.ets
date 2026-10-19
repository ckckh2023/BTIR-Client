import { PageHeader } from '../components/PageHeader';
import { AppTheme } from '../common/AppTheme';
import { AuthService } from '../service/AuthService';
import { ApiError } from '../common/ApiError';
import { buffer } from '@kit.ArkTS';
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
    if (!this.currentPassword) {
      this.errorMessage = '请输入当前密码';
      return;
    }
    if (!this.newPassword) {
      this.errorMessage = '请输入新密码';
      return;
    }
    if (this.newPassword.length < 6 || this.newPassword.length > 72) {
      this.errorMessage = '新密码长度应为 6 至 72 个字符';
      return;
    }
    const utf8ByteLength = buffer.from(this.newPassword, 'utf-8').length;
    if (utf8ByteLength > 72) {
      this.errorMessage = '密码的 UTF-8 编码不能超过 72 字节';
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
    PageHeader({ title: '修改密码', showBack: false, canLeave: !this.isLoading })
    Scroll() {
    Column() {
      // 标题区域
      Column() {
        Text('修改密码')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.primary)
          .margin({ top: 24 })

        Text('首次登录需要修改临时密码')
          .fontSize(14)
          .fontColor(AppTheme.muted)
          .margin({ top: 8 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 40 })

      // 输入表单
      Column() {
        TextInput({ placeholder: '请输入当前密码' })
          .width('100%')
          .height(48)
          .fontSize(16)
          .type(InputType.Password)
          .backgroundColor(AppTheme.subtle)
          .borderRadius(AppTheme.buttonRadius)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.currentPassword = value;
            this.errorMessage = '';
          })
          .margin({ bottom: 16 })

        TextInput({ placeholder: '6-72 个字符' })
          .width('100%')
          .height(48)
          .fontSize(16)
          .type(InputType.Password)
          .backgroundColor(AppTheme.subtle)
          .borderRadius(AppTheme.buttonRadius)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.newPassword = value;
            this.errorMessage = '';
          })
          .margin({ bottom: 16 })

        TextInput({ placeholder: '再次输入新密码' })
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
          .margin({ bottom: 8 })
      }
      .width('85%')
      .padding({ left: 20, right: 20 })

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

      // 修改密码按钮
      Button(this.isLoading ? '提交中...' : '确认修改')
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
          this.handleChangePassword();
        })
    }
    .width('100%')
    .padding({ top: 24, bottom: 32 })
    }
    .width('100%')
    .layoutWeight(1).align(Alignment.Top)
    .scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(AppTheme.background)
  }
}
