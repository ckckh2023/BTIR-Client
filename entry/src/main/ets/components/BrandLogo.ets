import { AppTheme } from '../common/AppTheme';
import { activateLogo } from '../common/AppNavigation';

@Component
export struct BrandLogo {
  @Prop compact: boolean = false;
  @Prop onHome: boolean = false;
  @Prop isEnabled: boolean = true;

  build() {
    Row({ space: 8 }) {
      Image($r('app.media.brand_logo')).width(this.compact ? 30 : 36).height(this.compact ? 30 : 36)
        .objectFit(ImageFit.Contain)
        .colorFilter(new ColorFilter([0.1216, 0, 0, 0, 0, 0, 0.2784, 0, 0, 0, 0, 0, 0.4902, 0, 0, 0, 0, 0, 1, 0]))
      if (!this.compact) Text('智瞳医脑').fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppTheme.primary)
    }
    .constraintSize({ minWidth: AppTheme.buttonHeight, minHeight: AppTheme.buttonHeight })
    .justifyContent(FlexAlign.Center)
    .id(this.onHome ? 'brand-about' : 'brand-home')
    .borderRadius(AppTheme.buttonRadius)
    .enabled(this.isEnabled)
    .accessibilityText(this.onHome ? '关于智瞳医脑' : '返回主页')
    .onClick(() => { activateLogo(this.onHome); })
  }
}
