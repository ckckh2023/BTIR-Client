import { PageHeader } from '../components/PageHeader';
import { AppTheme } from '../common/AppTheme';
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { SampleService, SampleDownloadCancelled } from '../service/SampleService';
import { SAMPLE_CASES, SampleCase, sampleSizeText } from '../common/SampleCatalog';

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
  @State videoVisible: boolean = false;
  @State videoError: boolean = false;
  @State videoLoading: boolean = true;

  onPageShow(): void { this.videoVisible = true; this.videoLoading = true; }
  onPageHide(): void { this.videoVisible = false; }

  aboutToDisappear(): void {
    this.videoVisible = false;
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
        this.message = `${sample.title}已保存`;
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

  @Builder
  BaselineMetric(label: string, value: number) {
    Column({ space: 6 }) {
      Text(label).fontSize(12).fontColor(AppTheme.secondary)
      Text(`${value.toFixed(1)} cm³`).fontSize(14).fontWeight(FontWeight.Bold).fontColor(AppTheme.text)
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      PageHeader({ title: '测试样例使用说明', canLeave: this.phase !== 'saving',
        onBack: (): void => { this.service.cancel(); router.back(); } })
      Scroll() {
        Column({ space: 24 }) {
          Column({ space: 14 }) {
            Text('下载一个测试病例').fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppTheme.text).width('100%')
            Text('每个 ZIP 包含同一病例的四模态 NIfTI 文件').fontSize(13).fontColor(AppTheme.secondary).width('100%')
            if (this.videoError) {
              Column({ space: 12 }) {
                Text('视频暂时无法播放').fontSize(14).fontColor(AppTheme.secondary)
                Button('重新加载').height(AppTheme.buttonHeight).borderRadius(AppTheme.buttonRadius)
                  .backgroundColor(AppTheme.disabled).fontColor(AppTheme.primary)
                  .onClick(() => { this.videoLoading = true; this.videoError = false; })
              }.width('100%').aspectRatio(16 / 9).justifyContent(FlexAlign.Center)
            } else if (this.videoVisible) {
              Stack() {
                Video({ src: $rawfile('upload-demo.mp4') }).width('100%').aspectRatio(16 / 9)
                  .autoPlay(true).muted(true).loop(true).controls(true).objectFit(ImageFit.Contain)
                  .onPrepared(() => { if (this.videoVisible) this.videoLoading = false; })
                  .onError(() => { if (this.videoVisible) { this.videoLoading = false; this.videoError = true; } })
                if (this.videoLoading) LoadingProgress().width(32).height(32).color(AppTheme.primary).hitTestBehavior(HitTestMode.None)
              }.width('100%').aspectRatio(16 / 9).clip(true).borderRadius(AppTheme.buttonRadius)
            }
            ForEach(SAMPLE_CASES, (sample: SampleCase) => {
              Column({ space: 6 }) {
                Text(sample.fileName).fontSize(14).fontWeight(FontWeight.Medium).fontColor(AppTheme.text).width('100%')
                Text(sampleSizeText(sample.sizeBytes)).fontSize(13).fontColor(AppTheme.muted).width('100%')
                Button(this.activeFile === sample.fileName
                  ? (this.phase === 'picking' ? '选择保存位置…' : this.progress) : `下载${sample.title}`)
                  .width('100%').height(AppTheme.buttonHeight).fontSize(14).borderRadius(AppTheme.buttonRadius)
                  .backgroundColor(AppTheme.primary).fontColor(AppTheme.surface).enabled(!this.activeFile)
                  .margin({ top: 6 }).onClick(() => { this.downloadSample(sample); })
                if (this.activeFile === sample.fileName && this.phase === 'downloading') {
                  Button('取消下载').height(AppTheme.buttonHeight).fontSize(13).borderRadius(AppTheme.buttonRadius)
                    .fontColor(AppTheme.secondary).backgroundColor(AppTheme.surface).onClick(() => { this.service.cancel(); })
                }
              }.width('100%').padding(14).backgroundColor(AppTheme.surface).borderRadius(AppTheme.buttonRadius)
                .border({ width: 1, color: AppTheme.border })
            }, (sample: SampleCase) => sample.fileName)
            if (this.message) {
              Text(this.message).fontSize(14).fontColor(this.isError ? AppTheme.danger : AppTheme.success)
                .width('100%').padding(12).backgroundColor(this.isError ? AppTheme.dangerBackground : AppTheme.successBackground)
                .borderRadius(AppTheme.buttonRadius)
            }
          }.width('100%').padding(16).backgroundColor(AppTheme.subtle).borderRadius(AppTheme.cardRadius)
            .border({ width: 1, color: AppTheme.border })

          Column({ space: 12 }) {
            Text('测试样例使用说明').fontSize(19).fontWeight(FontWeight.Bold).fontColor(AppTheme.text).width('100%')
            Text('上传 ZIP').fontSize(16).fontWeight(FontWeight.Bold).fontColor(AppTheme.text).width('100%')
            Text('1. 返回病例分析页\n2. 选择刚下载的一个 ZIP\n3. 确认文件后，点击“开始数据分析”')
              .fontSize(14).lineHeight(26).fontColor(AppTheme.secondary).width('100%')
            Text('每次分析只上传一个病例 ZIP').fontSize(13).fontColor(AppTheme.primary).width('100%')
              .padding(12).backgroundColor(AppTheme.selected).borderRadius(AppTheme.buttonRadius)
            Text('查看分析结果').fontSize(16).fontWeight(FontWeight.Bold).fontColor(AppTheme.text).width('100%')
            Text('查看综合结果、影像学关键特征、模型依据和重点层切片；同一病例可新增复查并对比。点击左上角 Logo 返回病例分析页。')
              .fontSize(14).lineHeight(24).fontColor(AppTheme.secondary).width('100%')
          }.width('100%')

          Column({ space: 14 }) {
            Text('样例核对').fontSize(19).fontWeight(FontWeight.Bold).fontColor(AppTheme.text).width('100%')
            Text('当前项目模型基准结果').fontSize(13).fontColor(AppTheme.secondary).width('100%')
            ForEach(SAMPLE_CASES, (sample: SampleCase) => {
              Column({ space: 12 }) {
                Text(sample.fileName).fontSize(13).fontWeight(FontWeight.Medium).fontColor(AppTheme.text).width('100%')
                Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.End }) {
                  Text(`${sample.probability.toFixed(2)}%`).fontSize(26).fontWeight(FontWeight.Bold).fontColor(AppTheme.primary)
                  Text('分类肿瘤概率').fontSize(12).fontColor(AppTheme.secondary).margin({ left: 8, bottom: 4 })
                }.width('100%')
                Row({ space: 8 }) {
                  this.BaselineMetric('WT', sample.wtCm3)
                  this.BaselineMetric('TC', sample.tcCm3)
                  this.BaselineMetric('ET', sample.etCm3)
                }.width('100%')
              }.width('100%').padding(14).backgroundColor(AppTheme.surface).borderRadius(AppTheme.buttonRadius)
                .border({ width: 1, color: AppTheme.border })
            }, (sample: SampleCase) => sample.fileName)
            Text('分类概率与分割体积存在少量浮动时，可视为正常推理差异').fontSize(13).lineHeight(22).fontColor(AppTheme.secondary).width('100%')
          }.width('100%').padding(16).backgroundColor(AppTheme.subtle).borderRadius(AppTheme.cardRadius)
            .border({ width: 1, color: AppTheme.border })
        }.width('100%').padding(16).backgroundColor(AppTheme.surface).borderRadius(AppTheme.cardRadius)
          .border({ width: 1, color: AppTheme.border })
          .margin({ top: 16, bottom: 24 })
      }.width('100%').padding({ left: 16, right: 16 }).layoutWeight(1).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(AppTheme.background)
  }
}
