import { PageHeader } from '../components/PageHeader';
import { AppTheme } from '../common/AppTheme';
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { webview } from '@kit.ArkWeb';
import { buffer } from '@kit.ArkTS';
import { TaskService } from '../service/TaskService';
import { TaskStatusResponse, PreviewFrame } from '../model/TaskModels';
import { ApiError } from '../common/ApiError';
import { TokenManager } from '../common/HttpClient';

import { buildReportHtml, ReportImage } from '../common/ReportPresentation';

@Entry
@Component
struct ReportExportPage {
  @State taskId: string = '';
  @State reportUrl: string = '';
  @State isLoading: boolean = true;
  @State isReady: boolean = false;
  @State isSaving: boolean = false;
  @State message: string = '';
  @State isError: boolean = false;
  private reportPath: string = '';
  private prepareVersion: number = 0;
  private preparing: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private taskService: TaskService = new TaskService();

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    this.taskId = params ? params['taskId'] ?? '' : '';
    if (this.taskId) {
      this.prepareReport();
    } else {
      this.message = '缺少任务 ID';
      this.isError = true;
      this.isLoading = false;
    }
  }

  aboutToDisappear(): void {
    this.prepareVersion++;
    if (this.reportPath) {
      try {
        fs.unlinkSync(this.reportPath);
      } catch (error) {
        // 缓存报告可能已被系统清理。
      }
      this.reportPath = '';
    }
  }

  private async loadReportImages(task: TaskStatusResponse): Promise<ReportImage[]> {
    const resultFiles = task.frontend_result?.result_files;
    if (!resultFiles) return [];
    const paths: string[] = [];
    const labels: string[] = [];
    if (resultFiles.preview) {
      paths.push(resultFiles.preview);
      labels.push('分析预览');
    }
    const frames = resultFiles.preview_series?.frames || [];
    for (let index = 0; index < Math.min(frames.length, 3); index++) {
      const frame: PreviewFrame = frames[index];
      const path = frame.overlay || frame.raw;
      if (path && !paths.includes(path)) {
        paths.push(path);
        labels.push(`切片 ${frame.slice_index}`);
      }
    }
    const images: ReportImage[] = [];
    for (let offset = 0; offset < paths.length; offset += 3) {
      const batch = paths.slice(offset, offset + 3);
      const results = await Promise.all(batch.map(async (path: string, index: number): Promise<ReportImage | null> => {
        try {
          const data = await this.taskService.downloadFile(task.task_id, path);
          return { label: labels[offset + index], dataUrl: `data:image/png;base64,${buffer.from(data).toString('base64')}` };
        } catch (error) { return null; }
      }));
      results.forEach((image: ReportImage | null) => { if (image) images.push(image); });
    }
    return images;
  }

  private async prepareReport(): Promise<void> {
    if (this.preparing) return;
    this.preparing = true;
    const version = ++this.prepareVersion;
    this.isLoading = true;
    this.isReady = false;
    this.message = '';
    this.isError = false;
    this.reportUrl = '';
    if (this.reportPath) {
      try { fs.unlinkSync(this.reportPath); } catch (error) { /* 清理旧预览缓存。 */ }
      this.reportPath = '';
    }
    try {
      const task = await this.taskService.getTask(this.taskId);
      if (task.status !== 'succeeded' && task.status !== 'partial') {
        throw new ApiError(400, '任务尚未完成', '请在分析完成后导出报告');
      }
      const images = await this.loadReportImages(task);
      if (version !== this.prepareVersion) return;
      const html = buildReportHtml(task, images);
      const context = getContext(this) as common.UIAbilityContext;
      const path = `${context.cacheDir}/btir-report-${Date.now()}.html`;
      const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        const bytes = buffer.from(html, 'utf8');
        let offset = 0;
        while (offset < bytes.length) {
          const size = Math.min(64 * 1024, bytes.length - offset);
          const block = new ArrayBuffer(size);
          new Uint8Array(block).set(new Uint8Array(bytes.buffer, bytes.byteOffset + offset, size));
          const written = fs.writeSync(file.fd, block);
          if (written <= 0) throw new Error('写入报告预览失败');
          offset += written;
        }
      } finally {
        await fs.close(file);
      }
      if (version !== this.prepareVersion) { await fs.unlink(path); return; }
      this.reportPath = path;
      this.reportUrl = `file://${path}`;
    } catch (error) {
      if (version !== this.prepareVersion) return;
      if (error instanceof ApiError && error.isTokenExpired()) {
        TokenManager.getInstance().clearAuth();
        router.replaceUrl({ url: 'pages/LoginPage' });
        return;
      }
      this.message = `准备报告失败：${error instanceof ApiError ? error.message : String(error)}`;
      this.isError = true;
    } finally {
      if (version === this.prepareVersion) this.isLoading = false;
      this.preparing = false;
    }
  }

  private async savePdf(): Promise<void> {
    if (!this.isReady || this.isSaving) return;
    this.isSaving = true;
    this.message = '';
    try {
      const pdf = await this.controller.createPdf({
        width: 8.27, height: 11.69,
        marginTop: 0.45, marginBottom: 0.45, marginLeft: 0.4, marginRight: 0.4,
        scale: 1, shouldPrintBackground: true
      });
      const bytes = pdf.pdfArrayBuffer();
      if (bytes.length < 5 || bytes[0] !== 0x25 || bytes[1] !== 0x50 || bytes[2] !== 0x44 ||
        bytes[3] !== 0x46 || bytes[4] !== 0x2d) {
        throw new Error('PDF 生成失败');
      }
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [`BTIR-${this.taskId.replace(/[^A-Za-z0-9_-]/g, '_')}.pdf`];
      options.fileSuffixChoices = ['PDF|.pdf'];
      const documentPicker = new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext);
      const uris = await documentPicker.save(options);
      if (!uris || uris.length === 0) return;
      const destination = await fs.open(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        let offset = 0;
        while (offset < bytes.length) {
          const size = Math.min(64 * 1024, bytes.length - offset);
          const block = new ArrayBuffer(size);
          new Uint8Array(block).set(bytes.subarray(offset, offset + size));
          const written = fs.writeSync(destination.fd, block);
          if (written <= 0) throw new Error('写入 PDF 失败');
          offset += written;
        }
      } finally {
        await fs.close(destination);
      }
      this.message = '报告 PDF 已保存到所选位置';
      this.isError = false;
    } catch (error) {
      this.message = `导出失败：${String(error)}`;
      this.isError = true;
    } finally {
      this.isSaving = false;
    }
  }

  build() {
    Column() {
      PageHeader({ title: '报告预览', canLeave: !this.isSaving,
        actionLabel: this.isSaving ? '生成中…' : '保存 PDF', actionEnabled: this.isReady && !this.isSaving,
        onAction: (): void => { this.savePdf(); } })

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(48).height(48).color(AppTheme.primary)
          Text('正在准备报告...').fontSize(14).fontColor(AppTheme.secondary).margin({ top: 12 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.reportUrl) {
        Web({ src: this.reportUrl, controller: this.controller })
          .fileAccess(true)
          .onPageEnd((event) => {
            if (event.url === this.reportUrl) this.isReady = true;
          })
          .onErrorReceive((event) => {
            if (event.request.isMainFrame()) {
              this.message = `报告预览失败：${event.error.getErrorInfo()}`;
              this.isError = true;
              this.isReady = false;
            }
          })
          .width('100%')
          .layoutWeight(1)
      }

      if (this.isError && !this.isLoading && !this.isSaving) {
        Button('重新准备报告').height(AppTheme.buttonHeight).backgroundColor(AppTheme.disabled).fontColor(AppTheme.primary)
          .onClick(() => { this.prepareReport(); })
      }
      if (this.message) {
        Text(this.message)
          .fontSize(13)
          .fontColor(this.isError ? AppTheme.danger : AppTheme.success)
          .width('90%')
          .padding(10)
          .backgroundColor(this.isError ? AppTheme.dangerBackground : AppTheme.successBackground)
          .borderRadius(AppTheme.buttonRadius)
          .margin({ bottom: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background)
  }
}
