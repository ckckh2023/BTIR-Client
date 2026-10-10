import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { SAMPLE_CASES, SampleCase, SampleService, SampleDownloadCancelled } from '../service/SampleService';

@Entry
@Component
struct SampleDownloadPage {
  @State activeFile: string = '';
  @State phase: string = '';
  @State progress: string = '';
  @State message: string = '';
  @State isError: boolean = false;
  private service: SampleService = new SampleService();
  private pageActive: boolean = true;

  aboutToBeDeleted(): void {
    this.pageActive = false;
    this.service.cancel();
  }

  private async downloadSample(sample: SampleCase): Promise<void> {
    if (this.activeFile) return;
    this.activeFile = sample.fileName;
    this.phase = 'picking';
    this.message = '';
    this.isError = false;
    let cachePath = '';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [sample.fileName];
      options.fileSuffixChoices = ['ZIP|.zip'];
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris = await documentPicker.save(options);
      if (!this.pageActive || !uris || uris.length === 0) return;
      this.phase = 'downloading';
      this.progress = '正在连接…';
      cachePath = await this.service.download(sample, context.cacheDir, (received: number, total: number) => {
        if (!this.pageActive) return;
        this.progress = total > 0
          ? `正在下载 ${Math.min(99, Math.floor(received * 100 / total))}%`
          : `已下载 ${(received / 1024 / 1024).toFixed(1)} MB`;
      });
      if (!this.pageActive) return;
      this.phase = 'saving';
      this.progress = '正在保存…';
      const destination = await fs.open(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        await fs.copyFile(cachePath, destination.fd);
      } finally {
        await fs.close(destination);
      }
      if (this.pageActive) {
        this.message = `${sample.title}样例已保存到所选位置。返回上传页，选择这个 ZIP 后即可开始分析。`;
      }
    } catch (error) {
      if (this.pageActive) {
        this.isError = !(error instanceof SampleDownloadCancelled);
        this.message = error instanceof SampleDownloadCancelled ? '已取消下载' :
          `下载未完成：${(error as Error).message || '请检查网络及设备剩余空间后重试'}`;
      }
    } finally {
      if (cachePath) {
        try { fs.unlinkSync(cachePath); } catch (error) { /* 缓存文件可能已清理。 */ }
      }
      if (this.pageActive) {
        this.activeFile = '';
        this.phase = '';
        this.progress = '';
      }
    }
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .height(32)
          .fontSize(12)
          .backgroundColor('#586b82')
          .fontColor('#ffffff')
          .borderRadius(6)
          .enabled(this.phase !== 'saving')
          .onClick(() => {
            this.service.cancel();
            router.back();
          })
        Blank()
        Text('测试样例')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1e2d3e')
        Blank()
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#ffffff')

      Scroll() {
        Column() {
          Text('与网页端相同的三个 BraTS 测试病例，每个 ZIP 包含 FLAIR、T1CE、T1、T2 四模态 NIfTI 文件。')
            .fontSize(14)
            .fontColor('#586b82')
            .width('100%')
            .margin({ bottom: 16 })

          ForEach(SAMPLE_CASES, (sample: SampleCase) => {
            Column() {
              Text(sample.title)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1e2d3e')
                .width('100%')
              Text(sample.fileName)
                .fontSize(13)
                .fontColor('#586b82')
                .width('100%')
                .margin({ top: 6, bottom: 12 })
              Button(this.activeFile === sample.fileName
                ? (this.phase === 'picking' ? '选择保存位置…' : this.progress) : '下载 ZIP')
                .width('100%')
                .height(40)
                .fontSize(14)
                .backgroundColor('#e6edf5')
                .fontColor('#1f477d')
                .borderRadius(8)
                .enabled(!this.activeFile)
                .onClick(() => { this.downloadSample(sample); })
              if (this.activeFile === sample.fileName && this.phase === 'downloading') {
                Button('取消下载')
                  .height(36)
                  .fontSize(12)
                  .fontColor('#586b82')
                  .backgroundColor('#f7f9fc')
                  .borderRadius(8)
                  .margin({ top: 8 })
                  .onClick(() => { this.service.cancel(); })
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#ffffff')
            .borderRadius(12)
            .margin({ bottom: 12 })
          }, (sample: SampleCase) => sample.fileName)

          if (this.message) {
            Text(this.message)
              .fontSize(13)
              .fontColor(this.isError ? '#b42318' : '#1f477d')
              .width('100%')
              .padding(12)
              .backgroundColor(this.isError ? '#fee2e2' : '#eaf2ff')
              .borderRadius(8)
              .margin({ bottom: 12 })
          }

          Text('使用方法：选择样例和保存位置 → 返回上传页选择已下载的 ZIP → 开始数据分析。每次只上传一个病例 ZIP。')
            .fontSize(13)
            .fontColor('#586b82')
            .width('100%')
        }
        .width('90%')
        .padding({ top: 20, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f2f5f9')
  }
}
