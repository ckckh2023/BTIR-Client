import { router } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { TokenManager } from '../common/HttpClient';
import { BrandLogo } from './BrandLogo';

@Component
export struct PageHeader {
  @Prop title: string = '';
  @Prop onHome: boolean = false;
  @Prop showBack: boolean = true;
  @Prop canLeave: boolean = true;
  @Prop actionLabel: string = '';
  @Prop actionEnabled: boolean = true;
  onBack: () => void = (): void => { router.back(); };
  onAction: () => void = (): void => {};

  @Builder
  AccountMenu() {
    Menu() {
      MenuItem({ content: TokenManager.getInstance().username || '当前账号' }).enabled(false)
      MenuItem({ content: '退出登录' }).onClick(() => {
        TokenManager.getInstance().clearAuth();
        router.replaceUrl({ url: 'pages/LoginPage' }).then(() => { router.clear(); });
      })
    }
  }

  build() {
    Row({ space: 8 }) {
      BrandLogo({ compact: true, onHome: this.onHome, isEnabled: this.canLeave })
      Text(this.title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(AppTheme.text)
        .layoutWeight(1).textAlign(TextAlign.Start)
      if (this.actionLabel) {
        Button(this.actionLabel).height(AppTheme.buttonHeight).fontSize(13)
          .backgroundColor(AppTheme.surface).fontColor(AppTheme.primary).borderRadius(AppTheme.buttonRadius)
          .enabled(this.actionEnabled).onClick(() => { this.onAction(); })
      }
      if (this.onHome) {
        Button('账号').height(AppTheme.buttonHeight).fontSize(13)
          .backgroundColor(AppTheme.surface).fontColor(AppTheme.secondary).enabled(this.canLeave)
          .bindMenu(this.AccountMenu)
      } else if (this.showBack) {
        Button('返回').height(AppTheme.buttonHeight).fontSize(13)
          .backgroundColor(AppTheme.surface).fontColor(AppTheme.secondary).borderRadius(AppTheme.buttonRadius)
          .enabled(this.canLeave).onClick(() => { this.onBack(); })
      }
    }
    .width('100%').constraintSize({ minHeight: AppTheme.headerHeight })
    .padding({ left: AppTheme.pagePadding, right: AppTheme.pagePadding })
    .backgroundColor(AppTheme.surface).border({ width: { bottom: 1 }, color: AppTheme.border })
  }
}
