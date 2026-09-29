import { router } from '@kit.ArkUI';
import { TokenManager } from '../common/HttpClient';

@Entry
@Component
struct HomePage {
  @State username: string = '';

  aboutToAppear(): void {
    this.username = TokenManager.getInstance().username;
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('智瞳医脑')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A73E8')

        Blank()

        Text(this.username)
          .fontSize(14)
          .fontColor('#666666')
          .margin({ right: 8 })

        Button('退出')
          .height(32)
          .fontSize(12)
          .backgroundColor('#E53935')
          .onClick(() => {
            TokenManager.getInstance().clearAuth();
            router.replaceUrl({ url: 'pages/LoginPage' });
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 2, color: '#E0E0E0', offsetY: 2 })

      // 功能卡片区域
      Column() {
        // 病例分析卡片
        Column() {
          Row() {
            Text('病例分析')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
          }
          .width('100%')
          .margin({ bottom: 8 })

          Text('上传病例 ZIP 或 NIfTI 文件，启动 AI 辅助分析')
            .fontSize(14)
            .fontColor('#666666')
            .width('100%')
            .margin({ bottom: 16 })

          Button('开始上传病例')
            .width('100%')
            .height(44)
            .fontSize(16)
            .backgroundColor('#1A73E8')
            .borderRadius(8)
            .onClick(() => {
              router.pushUrl({ url: 'pages/UploadPage' });
            })
        }
        .width('100%')
        .padding(20)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .shadow({ radius: 4, color: '#E0E0E0', offsetY: 2 })
        .margin({ bottom: 16 })

        // 任务管理卡片
        Column() {
          Row() {
            Text('任务管理')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
          }
          .width('100%')
          .margin({ bottom: 8 })

          Text('查看历史病例、推理结果和随访对比')
            .fontSize(14)
            .fontColor('#666666')
            .width('100%')
            .margin({ bottom: 16 })

          Button('查看病例列表')
            .width('100%')
            .height(44)
            .fontSize(16)
            .backgroundColor('#4CAF50')
            .borderRadius(8)
            .onClick(() => {
              router.pushUrl({ url: 'pages/TaskListPage' });
            })
        }
        .width('100%')
        .padding(20)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .shadow({ radius: 4, color: '#E0E0E0', offsetY: 2 })
      }
      .width('90%')
      .margin({ top: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}
