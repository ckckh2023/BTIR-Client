import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { webview } from '@kit.ArkWeb';
import { buffer } from '@kit.ArkTS';
import { TaskService } from '../service/TaskService';
import { TaskStatusResponse, PreviewFrame } from '../model/TaskModels';
import { ApiError } from '../common/ApiError';
import { TokenManager } from '../common/HttpClient';

interface ReportImage {
  label: string;
  dataUrl: string;
}

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

  aboutToBeDeleted(): void {
    if (this.reportPath) {
      try {
        fs.unlinkSync(this.reportPath);
      } catch (error) {
        // 缓存报告可能已被系统清理。
      }
      this.reportPath = '';
    }
  }

  private escapeHtml(value: string): string {
    return value.replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  private text(value?: string): string {
    return this.escapeHtml(value || '未提供');
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
    for (let index = 0; index < paths.length; index++) {
      try {
        const data = await this.taskService.downloadFile(task.task_id, paths[index]);
        images.push({ label: labels[index], dataUrl: `data:image/png;base64,${buffer.from(data).toString('base64')}` });
      } catch (error) {
        // 报告文字仍可导出；某张预览图缺失时继续处理其他图。
      }
    }
    return images;
  }

  private buildHtml(task: TaskStatusResponse, images: ReportImage[]): string {
    const result = task.frontend_result;
    const sections: string[] = [];
    if (result?.model_consensus) {
      const consensus = result.model_consensus;
      sections.push(`<section><h2>综合结果</h2><p class="key">${this.text(consensus.summary)}</p>` +
        `<p>${this.text(consensus.primary_evidence)}</p>` +
        `<p>模型一致性：${consensus.consistency === 'consistent' ? '相互支持' : '请结合临床复核'}` +
        `${consensus.requires_review ? ' · 建议复核' : ''}</p></section>`);
    }
    if (result?.classification) {
      const classification = result.classification;
      const probabilityKeys: string[] = classification.probabilities
        ? Object.keys(classification.probabilities) : [];
      const probabilities = probabilityKeys.map((key: string) =>
        `<li>${this.text(key === 'yes' ? '异常' : key === 'no' ? '正常' : key)}：` +
        `${(classification.probabilities[key] * 100).toFixed(1)}%</li>`).join('');
      sections.push(`<section><h2>分类结论</h2><p class="key">${classification.class === 'yes' ? '提示肿瘤相关异常' : '未发现明显异常'}</p>` +
        `<p>置信度：${(classification.confidence * 100).toFixed(1)}%</p><ul>${probabilities}</ul>` +
        `${classification.experimental ? '<p class="note">此分类结果为实验性辅助分析，不作为确定诊断依据。</p>' : ''}</section>`);
    }
    if (result?.segmentation) {
      const regions = result.segmentation.regions;
      const rows = regions ? Object.keys(regions).map((key: string) =>
        `<tr><td>${this.text(regions[key].name || key)}</td><td>${regions[key].volume_mm3 === undefined ? '—' : regions[key].volume_mm3!.toFixed(1) + ' mm³'}</td></tr>`).join('') : '';
      sections.push(`<section><h2>分割结果</h2>${rows ? `<table><thead><tr><th>区域</th><th>体积</th></tr></thead><tbody>${rows}</tbody></table>` : '<p>暂无可量化区域。</p>'}</section>`);
    }
    if (result?.supplementary_analysis?.content) {
      const content = result.supplementary_analysis.content;
      const observations = (content.observations || []).map((item: string) => `<li>${this.text(item)}</li>`).join('');
      const uncertainties = (content.uncertainties || []).map((item: string) => `<li>${this.text(item)}</li>`).join('');
      sections.push(`<section><h2>AI 辅助分析</h2><p><strong>结论：</strong>${this.text(content.summary)}</p>` +
        `<p><strong>建议：</strong>${this.text(content.follow_up)}</p>` +
        `${observations ? `<h3>观察项</h3><ul>${observations}</ul>` : ''}` +
        `${uncertainties ? `<h3>不确定项</h3><ul>${uncertainties}</ul>` : ''}</section>`);
    }
    if (images.length > 0) {
      sections.push(`<section><h2>影像预览</h2><div class="images">${images.map((item: ReportImage) =>
        `<figure><img src="${item.dataUrl}" alt=""><figcaption>${this.text(item.label)}</figcaption></figure>`).join('')}</div></section>`);
    }
    const content = sections.length ? sections.join('') : '<section><p>当前任务尚无可导出的分析结果。</p></section>';
    return `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>` +
      `@page{size:A4;margin:14mm}*{box-sizing:border-box}html,body{width:100%;max-width:100%;overflow-x:hidden}` +
      `body{font:14px sans-serif;color:#1e2d3e;background:#fff;margin:0;padding:20px;line-height:1.6}` +
      `p,li,td,th,figcaption{overflow-wrap:anywhere;word-break:break-word;white-space:pre-wrap}` +
      `h1{color:#1f477d;font-size:24px;margin:0 0 6px}h2{color:#1f477d;font-size:17px;border-bottom:1px solid #d9e3ef;padding-bottom:6px}` +
      `h3{font-size:14px;margin:10px 0 4px}.sub{color:#586b82;font-size:12px}.key{font-weight:700;font-size:17px}` +
      `section{margin:18px 0}h2,h3{break-after:avoid}table{width:100%;table-layout:fixed;border-collapse:collapse}` +
      `td,th{border:1px solid #d9e3ef;padding:7px;text-align:left;vertical-align:top}` +
      `.note{background:#fffbeb;padding:8px}.images{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}` +
      `figure{margin:0;min-width:0;break-inside:avoid}img{display:block;max-width:100%;max-height:240px;object-fit:contain;background:#02060b}` +
      `figcaption{font-size:12px;color:#586b82;text-align:center}.foot{margin-top:24px;border-top:1px solid #d9e3ef;padding-top:8px;color:#586b82;font-size:11px}` +
      `</style></head><body><h1>智瞳医脑 · 病例分析报告</h1>` +
      `<p class="sub">病例：${this.text(task.case_name || task.name)}　检查日期：${this.text(task.study_date)}<br>` +
      `任务 ID：${this.text(task.task_id)}　状态：${this.text(task.status)}</p>${content}` +
      `<p class="foot">本报告由 AI 辅助分析生成，仅供专业人员参考，不替代临床诊断。</p></body></html>`;
  }

  private async prepareReport(): Promise<void> {
    this.isLoading = true;
    this.isReady = false;
    this.message = '';
    try {
      const task = await this.taskService.getTask(this.taskId);
      if (task.status !== 'succeeded' && task.status !== 'partial') {
        throw new ApiError(400, '任务尚未完成', '请在分析完成后导出报告');
      }
      const images = await this.loadReportImages(task);
      const html = this.buildHtml(task, images);
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
      this.reportPath = path;
      this.reportUrl = `file://${path}`;
    } catch (error) {
      if (error instanceof ApiError && error.isTokenExpired()) {
        TokenManager.getInstance().clearAuth();
        router.replaceUrl({ url: 'pages/LoginPage' });
        return;
      }
      this.message = `准备报告失败：${error instanceof ApiError ? error.message : String(error)}`;
      this.isError = true;
    } finally {
      this.isLoading = false;
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
      Row() {
        Button('返回')
          .height(32)
          .fontSize(12)
          .backgroundColor('#586b82')
          .fontColor('#ffffff')
          .borderRadius(6)
          .onClick(() => { router.back(); })
        Blank()
        Text('报告预览')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1e2d3e')
        Blank()
        Button(this.isSaving ? '生成中...' : '保存 PDF')
          .height(32)
          .fontSize(12)
          .backgroundColor('#1f477d')
          .fontColor('#ffffff')
          .borderRadius(6)
          .enabled(this.isReady && !this.isSaving)
          .onClick(() => { this.savePdf(); })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#ffffff')

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(48).height(48).color('#1f477d')
          Text('正在准备报告...').fontSize(14).fontColor('#586b82').margin({ top: 12 })
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

      if (this.message) {
        Text(this.message)
          .fontSize(13)
          .fontColor(this.isError ? '#b42318' : '#18794e')
          .width('90%')
          .padding(10)
          .backgroundColor(this.isError ? '#fee2e2' : '#dcfce7')
          .borderRadius(8)
          .margin({ bottom: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f2f5f9')
  }
}
