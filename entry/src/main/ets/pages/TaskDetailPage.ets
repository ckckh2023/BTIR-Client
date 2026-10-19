import { ProbabilityChart } from '../components/ProbabilityChart';
import { probabilitySeries } from '../common/ProbabilityPresentation';
import { PageHeader } from '../components/PageHeader';
import { AppTheme } from '../common/AppTheme';
import { router } from '@kit.ArkUI';
import { TaskService } from '../service/TaskService';
import { ApiError } from '../common/ApiError';
import { TokenManager } from '../common/HttpClient';
import { buffer } from '@kit.ArkTS';
import { AnalysisProgress } from '../common/AnalysisProgress';
import { TaskMonitor, MonitorFailure, taskRunChanged } from '../common/TaskMonitor';
import { PreviewLoader, PreviewImage } from '../common/PreviewLoader';
import { consensusTone, consensusLabel, evidenceLabel, imagingMetrics, ResultMetric,
  formatMeasure, validNumber, followUpHistory, formatDate, taskStatusLabel, classificationLabel, formatProbability } from '../common/ResultPresentation';
import {
  TaskStatusResponse,
  ClassificationResult,
  SegmentationResult,
  ModelConsensus,
  SupplementaryAnalysis,
  FrontendResult,
  TaskFollowUpResponse,
  TaskFollowUpHistoryItem,
} from '../model/TaskModels';

interface FollowUpMetric {
  key: string;
  label: string;
  baseline: string;
  current: string;
  change: string;
}

@Entry
@Component
struct TaskDetailPage {
  @StorageProp('system_top_inset') topInset: number = 24;
  @StorageProp('system_bottom_inset') bottomInset: number = 16;
  @State taskId: string = '';
  @State task: TaskStatusResponse | null = null;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State displayProgress: number = 0;
  @State progressPhase: string = 'idle';
  @State previewImages: PreviewImage[] = [];
  @State previewMode: string = 'overlay';
  @State previewIndex: number = 0;
  @State showFollowUpHistory: boolean = false;
  @State showRegionDetails: boolean = false;
  @State enlargedPreview: string = '';
  @State showLargePreview: boolean = false;
  @State previewScale: number = 1;
  private previewScaleBase: number = 1;
  @State isCancelling: boolean = false;
  @State isRetrying: boolean = false;
  @State isStarting: boolean = false;
  @State followUp: TaskFollowUpResponse | null = null;
  @State followUpLoading: boolean = false;
  @State followUpError: string = '';
  @State selectedFollowUpTaskId: string = '';
  @State showTechnicalDetails: boolean = false;
  private followUpLoadedFor: string = '';
  private pageVisible: boolean = false;
  private followUpVersion: number = 0;
  private animationTimer: number = -1;
  private progress: AnalysisProgress = new AnalysisProgress();
  private taskService: TaskService = new TaskService();
  private previewLoader: PreviewLoader = new PreviewLoader(async (id: string, path: string): Promise<string> => {
    const data = await this.taskService.downloadFile(id, path);
    return `data:image/png;base64,${buffer.from(data).toString('base64')}`;
  });
  private monitor: TaskMonitor = new TaskMonitor(
    (id: string): Promise<TaskStatusResponse> => this.taskService.getTask(id),
    (response: TaskStatusResponse): void => { this.acceptTask(response); },
    (failure: MonitorFailure): void => { this.monitorFailed(failure); }
  );

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    this.taskId = params ? params['taskId'] || '' : '';
    if (!this.taskId) {
      this.isLoading = false;
      this.errorMessage = '缺少任务 ID，请返回病例列表重新打开';
    }
  }

  onPageShow(): void {
    this.pageVisible = true;
    this.fetchTask();
  }

  onPageHide(): void { this.pausePage(); }
  aboutToDisappear(): void { this.pausePage(); }

  private pausePage(): void {
    this.pageVisible = false;
    this.monitor.stop();
    this.stopAnimation();
    this.previewLoader.cancel();
    this.followUpVersion++;
    if (this.followUpLoading) this.followUpLoadedFor = '';
    this.followUpLoading = false;
  }

  async fetchTask(): Promise<void> {
    if (this.pageVisible && this.taskId) this.monitor.start(this.taskId);
  }

  private monitorFailed(failure: MonitorFailure): void {
    if (failure.error instanceof ApiError && failure.error.isTokenExpired()) {
      this.pausePage();
      TokenManager.getInstance().clearAuth();
      router.replaceUrl({ url: 'pages/LoginPage' });
      return;
    }
    this.isLoading = false;
    this.stopAnimation();
    const retry = failure.retryInMs > 0 ? `，${Math.ceil(failure.retryInMs / 1000)} 秒后自动重试` : '';
    this.errorMessage = `${failure.error.message}${retry}`;
  }

  private acceptTask(response: TaskStatusResponse): void {
    if (!this.pageVisible) return;
    if (taskRunChanged(this.task, response)) this.clearRunView();
    this.task = response;
    this.errorMessage = '';
    this.isLoading = false;
    this.progress.updateTask(response.status, response.progress);
    this.progressPhase = this.progress.phase;
    if (response.status === 'succeeded') {
      this.displayProgress = Math.max(this.displayProgress, this.progress.mappedPercent);
    }
    this.stopAnimation();
    if (response.status === 'running' || response.status === 'queued') {
      this.displayProgress = Math.max(this.displayProgress, this.progress.mappedPercent);
      this.animationTimer = setInterval(() => {
        this.displayProgress = this.progress.advance(this.displayProgress, Date.now());
      }, 50);
    }
    if (response.status === 'succeeded' || response.status === 'partial') {
      this.loadPreviewImages(response);
      if (this.followUpLoadedFor !== response.task_id) this.loadFollowUp(response.task_id);
    }
  }

  private stopAnimation(): void {
    if (this.animationTimer >= 0) clearInterval(this.animationTimer);
    this.animationTimer = -1;
    this.progress.pause();
  }

  private resetRun(): void {
    this.monitor.stop();
    this.clearRunView();
    this.task = null;
    this.isLoading = true;
  }

  private clearRunView(): void {
    this.stopAnimation();
    this.progress.reset();
    this.displayProgress = 10;
    this.progressPhase = 'queued';
    this.previewLoader.clear();
    this.previewImages = [];
    this.previewIndex = 0;
    this.showFollowUpHistory = false;
    this.showRegionDetails = false;
    this.followUpLoadedFor = '';
    this.followUpVersion++;
    this.followUp = null;
    this.selectedFollowUpTaskId = '';
    this.followUpLoading = false;
  }

  async loadPreviewImages(task: TaskStatusResponse): Promise<void> {
    await this.previewLoader.load(task, (items: PreviewImage[]): void => {
      if (this.pageVisible && this.taskId === task.task_id) this.previewImages = items;
    });
  }

  private previewFrames(): PreviewImage[] {
    const frames = this.previewImages.filter((item: PreviewImage) => item.kind === this.previewMode);
    return frames.length ? frames : this.previewImages.filter((item: PreviewImage) => item.kind === 'overview');
  }

  private selectPreviewMode(mode: string): void {
    this.previewMode = mode;
    this.previewIndex = Math.min(this.previewIndex, Math.max(0, this.previewFrames().length - 1));
  }

  private shownPreviews(): PreviewImage[] {
    const frames = this.previewFrames();
    return frames.length ? [frames[Math.min(this.previewIndex, frames.length - 1)]] : [];
  }

  private stageText(): string {
    if (this.task?.status === 'queued') return '任务排队中，等待处理';
    if (this.task?.progress_stage) return this.task.progress_stage;
    return this.progressPhase === 'summary' ? '正在生成综合分析…' :
      this.progressPhase === 'segmentation' ? '分割推理中…' : '分类推理准备中…';
  }

  private hasPreviewErrors(): boolean { return this.previewImages.some((item: PreviewImage) => item.error); }

  private historyItems(): TaskFollowUpHistoryItem[] { return followUpHistory(this.followUp); }
  private date(value?: string): string { return formatDate(value); }
  private measure(value?: number): string { return formatMeasure(value); }
  private resultMetrics(): ResultMetric[] { return this.task?.frontend_result?.segmentation ? imagingMetrics(this.task.frontend_result.segmentation) : []; }
  private conclusion(consensus: ModelConsensus): string { return consensusLabel(consensus, this.task?.frontend_result?.classification); }
  private evidence(consensus: ModelConsensus): string { return evidenceLabel(consensus.primary_evidence); }

  private async loadFollowUp(taskId: string): Promise<void> {
    const version = ++this.followUpVersion;
    this.followUpLoadedFor = taskId;
    this.followUpLoading = true;
    this.followUpError = '';
    try {
      const response = await this.taskService.getFollowUp(taskId);
      if (!this.pageVisible || version !== this.followUpVersion || taskId !== this.taskId) return;
      this.followUp = response;
      this.selectedFollowUpTaskId = response.baseline?.task_id ||
        (this.historyItems()[0]?.task.task_id || '');
    } catch (error) {
      if (!this.pageVisible || version !== this.followUpVersion) return;
      if (error instanceof ApiError && error.isTokenExpired()) {
        TokenManager.getInstance().clearAuth();
        router.replaceUrl({ url: 'pages/LoginPage' });
        return;
      }
      this.followUpError = `读取随访记录失败：${error instanceof ApiError ? error.message : String(error)}`;
      this.followUpLoadedFor = '';
    } finally {
      if (version === this.followUpVersion) this.followUpLoading = false;
    }
  }

  private startFollowUp(): void {
    if (!this.task) return;
    router.pushUrl({
      url: 'pages/UploadPage',
      params: {
        followUp: 'true',
        caseId: this.task.case_id || this.task.task_id,
        caseName: this.task.case_name || this.task.name || '当前病例'
      }
    });
  }

  private selectedFollowUp(): TaskFollowUpHistoryItem | null {
    const items = this.historyItems();
    return items.find((item: TaskFollowUpHistoryItem) => item.task.task_id === this.selectedFollowUpTaskId) || items[0] || null;
  }

  private validValue(value?: number): number | undefined {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : undefined;
  }

  private volumeValue(result: FrontendResult | undefined, key: string): number | undefined {
    return this.validValue(result?.segmentation?.composites?.[key]?.volume_mm3);
  }

  private areaValue(result: FrontendResult | undefined): number | undefined {
    return this.validValue(result?.segmentation?.morphology?.max_axial_area_mm2);
  }

  private probabilityValue(result: FrontendResult | undefined): number | undefined {
    return this.validValue(result?.classification?.probabilities?.['yes']);
  }

  private appendMetric(metrics: FollowUpMetric[], key: string, label: string,
    unit: string, baselineValue?: number, currentValue?: number): void {
    if (baselineValue === undefined || currentValue === undefined) return;
    const delta = currentValue - baselineValue;
    const sign = delta > 0 ? '+' : '';
    const percent = baselineValue > 0 ? ` · ${sign}${(delta / baselineValue * 100).toFixed(1)}%` : '';
    const probability = unit === 'probability';
    const suffix = unit === 'area' ? ' mm²' : ' mm³';
    metrics.push({
      key: key,
      label: label,
      baseline: probability ? `${(baselineValue * 100).toFixed(1)}%` : `${baselineValue.toFixed(1)}${suffix}`,
      current: probability ? `${(currentValue * 100).toFixed(1)}%` : `${currentValue.toFixed(1)}${suffix}`,
      change: probability ? `${sign}${(delta * 100).toFixed(1)} 个百分点${percent}` :
        `${sign}${delta.toFixed(1)}${suffix}${percent}`
    });
  }

  private followUpMetrics(): FollowUpMetric[] {
    const selected = this.selectedFollowUp();
    const current = this.task?.frontend_result;
    if (!selected || !current) return [];
    const baseline = selected.frontend_result;
    const metrics: FollowUpMetric[] = [];
    this.appendMetric(metrics, 'wt', '全肿瘤体积', 'volume',
      this.volumeValue(baseline, 'WT'), this.volumeValue(current, 'WT'));
    this.appendMetric(metrics, 'tc', '肿瘤核心体积', 'volume',
      this.volumeValue(baseline, 'TC'), this.volumeValue(current, 'TC'));
    this.appendMetric(metrics, 'et', '强化肿瘤体积', 'volume',
      this.volumeValue(baseline, 'ET'), this.volumeValue(current, 'ET'));
    this.appendMetric(metrics, 'area', '最大横截面积', 'area',
      this.areaValue(baseline), this.areaValue(current));
    this.appendMetric(metrics, 'probability', '肿瘤相关概率', 'probability',
      this.probabilityValue(baseline), this.probabilityValue(current));
    return metrics;
  }

  getStatusColor(status: string): string {
    switch (status) {
      case 'succeeded':
        return AppTheme.success;
      case 'failed':
        return AppTheme.danger;
      case 'canceled':
        return AppTheme.secondary;
      case 'running':
        return AppTheme.accent;
      case 'queued':
        return AppTheme.accent;
      case 'cancel_requested':
        return AppTheme.accent;
      case 'partial':
        return AppTheme.secondary;
      default:
        return AppTheme.secondary;
    }
  }

  getStatusText(status: string): string { return taskStatusLabel(status); }

  getStatusBgColor(status: string): string {
    switch (status) {
      case 'succeeded':
        return AppTheme.successBackground;
      case 'failed':
        return AppTheme.dangerBackground;
      case 'canceled':
        return AppTheme.disabled;
      case 'running':
        return AppTheme.selected;
      case 'queued':
        return AppTheme.selected;
      case 'cancel_requested':
        return AppTheme.selected;
      case 'partial':
        return AppTheme.disabled;
      default:
        return AppTheme.disabled;
    }
  }

  getPhaseColor(index: number): string {
    const state = this.progress.phaseState(index, this.task?.status || 'created');
    return state === 'done' ? AppTheme.success : state === 'active' ? AppTheme.accent : AppTheme.muted;
  }

  getPhaseBgColor(index: number): string {
    const state = this.progress.phaseState(index, this.task?.status || 'created');
    return state === 'done' ? AppTheme.successBackground : state === 'active' ? AppTheme.selected : AppTheme.disabled;
  }

  getConsensusTone(consensus: ModelConsensus): string {
    return consensusTone(consensus, this.task?.frontend_result?.classification);
  }

  getConsensusColor(tone: string): string {
    switch (tone) {
      case 'present':
        return AppTheme.danger;
      case 'absent':
        return AppTheme.success;
      case 'possible':
        return AppTheme.warning;
      case 'review':
        return AppTheme.warning;
      default:
        return AppTheme.text;
    }
  }

  getConsensusBgColor(tone: string): string {
    switch (tone) {
      case 'present':
        return '#fff4f4';
      case 'absent':
        return '#f0fdf4';
      case 'possible':
        return AppTheme.warningBackground;
      case 'review':
        return AppTheme.warningBackground;
      default:
        return AppTheme.surface;
    }
  }

  getRegionColor(key: string): string {
    switch (key) {
      case '1':
        return '#e53e3e';
      case '2':
        return '#22c55e';
      case '4':
        return '#facc15';
      default:
        return '#3d7fbd';
    }
  }

  getRegionName(key: string): string {
    switch (key) {
      case '1':
        return 'NCR/NET';
      case '2':
        return 'ED';
      case '4':
        return 'ET';
      default:
        return key;
    }
  }

  async handleCancel(): Promise<void> {
    if (this.isCancelling || this.isRetrying || this.isStarting) return;
    this.isCancelling = true;
    try {
      await this.taskService.cancelTask(this.taskId);
      await this.fetchTask();
    } catch (error) {
      this.errorMessage = `取消失败: ${error instanceof ApiError ? error.message : String(error)}`;
    } finally {
      this.isCancelling = false;
    }
  }

  async handleRetry(): Promise<void> {
    if (this.isCancelling || this.isRetrying || this.isStarting) return;
    this.isRetrying = true;
    try {
      await this.taskService.retryTask(this.taskId);
      this.resetRun();
      await this.fetchTask();
    } catch (error) {
      this.errorMessage = `重试失败: ${error instanceof ApiError ? error.message : String(error)}`;
    } finally {
      this.isRetrying = false;
    }
  }

  async handleStart(): Promise<void> {
    if (this.isCancelling || this.isRetrying || this.isStarting) return;
    this.isStarting = true;
    this.errorMessage = '';
    try {
      await this.taskService.runAsync(this.taskId);
      this.resetRun();
      await this.fetchTask();
    } catch (error) {
      const startError = `启动分析失败: ${error instanceof ApiError ? error.message : String(error)}`;
      await this.fetchTask();
      if (this.task?.status === 'created') {
        this.errorMessage = startError;
      }
    } finally {
      this.isStarting = false;
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      PageHeader({ title: '病例分析', canLeave: !this.isCancelling && !this.isRetrying && !this.isStarting,
        actionLabel: this.task?.status === 'succeeded' || this.task?.status === 'partial' ? '导出报告' : '',
        onAction: (): void => { router.pushUrl({ url: 'pages/ReportExportPage', params: { taskId: this.taskId } }); } })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(AppTheme.primary)
          Text('加载中...')
            .fontSize(14)
            .fontColor(AppTheme.secondary)
            .margin({ top: 16 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.task) {
        Scroll() {
          Column() {
            // 状态卡片
            Column() {
              Row() {
                Text(this.task!.name || '当前检查')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppTheme.text).layoutWeight(1).margin({ right: 8 })

                Text(this.getStatusText(this.task!.status))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.getStatusColor(this.task!.status))
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(this.getStatusBgColor(this.task!.status))
                  .borderRadius(6)
              }
              .width('100%')
              .margin({ bottom: 8 })

              if (this.task!.status === 'partial') {
                Text('本次分析仅部分完成，下方展示已有结果；报告可能不包含全部分析内容。')
                  .fontSize(13).fontColor(AppTheme.warning).width('100%').margin({ bottom: 10 })
              }
              if (this.task!.status === 'created') {
                Text('病例已上传，等待启动分析')
                  .fontSize(14)
                  .fontColor(AppTheme.secondary)
                  .width('100%')
                  .margin({ bottom: 8 })

                Button(this.isStarting ? '启动中...' : '启动分析')
                  .width('100%')
                  .height(AppTheme.buttonHeight)
                  .fontSize(14)
                  .backgroundColor(AppTheme.primary)
                  .fontColor(AppTheme.surface)
                  .borderRadius(AppTheme.buttonRadius)
                  .enabled(!this.isStarting)
                  .onClick(() => {
                    this.handleStart();
                  })
              }

              // 进度条 + 阶段指示器
              if (this.task!.status === 'running' || this.task!.status === 'queued' ||
                this.task!.status === 'cancel_requested') {
                // 阶段指示器
                Row() {
                  ForEach(['3D 分类', '3D 分割', '综合分析'], (phase: string, index: number) => {
                    Row() {
                      Text(phase)
                        .fontSize(12)
                        .fontColor(this.getPhaseColor(index))
                    }
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .borderRadius(AppTheme.cardRadius)
                    .backgroundColor(this.getPhaseBgColor(index))
                    .margin({ right: 8 })
                  })
                }
                .width('100%')
                .margin({ bottom: 8 })

                if (this.task!.status !== 'cancel_requested') {
                  Text(`整体进度 ${Math.floor(this.displayProgress)}%`)
                    .fontSize(13).fontColor(AppTheme.secondary).width('100%').margin({ bottom: 6 })
                  Progress({ value: this.displayProgress, total: 100, type: ProgressType.Linear })
                    .width('100%')
                    .color(AppTheme.primary)
                    .backgroundColor('#e8eef7')
                    .margin({ bottom: 8 })
                }

                if (this.task!.status === 'running' || this.task!.status === 'queued') {
                  Text(this.stageText())
                    .fontSize(14)
                    .fontColor(AppTheme.secondary)
                    .width('100%')
                }

                // 取消按钮
                Button(this.isCancelling ? '取消中...' : '取消任务')
                  .width('100%')
                  .height(AppTheme.buttonHeight)
                  .fontSize(14)
                  .backgroundColor(AppTheme.disabled)
                  .fontColor(AppTheme.danger)
                  .borderRadius(AppTheme.buttonRadius)
                  .enabled(!this.isCancelling && this.task!.status !== 'cancel_requested')
                  .margin({ top: 12 })
                  .onClick(() => {
                    this.handleCancel();
                  })
              }

              // 失败/取消状态操作
              if (this.task!.status === 'failed' || this.task!.status === 'canceled') {
                if (this.task!.error) {
                  Text(`错误: ${this.task!.error.message}`)
                    .fontSize(14)
                    .fontColor(AppTheme.danger)
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(AppTheme.dangerBackground)
                  .borderRadius(AppTheme.buttonRadius)
                  .margin({ top: 8 })
                }

                Button(this.isRetrying ? '重试中...' : '重试任务')
                  .width('100%')
                  .height(AppTheme.buttonHeight)
                  .fontSize(14)
                  .backgroundColor(AppTheme.primary)
                  .fontColor(AppTheme.surface)
                  .borderRadius(AppTheme.buttonRadius)
                  .enabled(!this.isRetrying)
                  .margin({ top: 12 })
                  .onClick(() => {
                    this.handleRetry();
                  })
              }
            }
            .width('100%')
            .padding(AppTheme.pagePadding)
            .backgroundColor(AppTheme.surface)
            .borderRadius(AppTheme.cardRadius)
            .margin({ bottom: 12 })

            if (this.task!.status === 'succeeded' || this.task!.status === 'partial') {
            // 综合结果
            if (this.task!.frontend_result?.model_consensus) {
              this.ConsensusCard(this.task!.frontend_result.model_consensus)
            }

            this.FollowUpCard()
            if (this.task!.frontend_result?.segmentation) this.SegmentationCard(this.task!.frontend_result.segmentation)
            if (this.task!.frontend_result?.classification) this.ClassificationCard(this.task!.frontend_result.classification)
            if (this.previewImages.length > 0) this.PreviewCard()
            if (this.task!.frontend_result?.supplementary_analysis?.content) this.SupplementaryCard(this.task!.frontend_result.supplementary_analysis)
            }

            // 任务信息
            Button(this.showTechnicalDetails ? '收起任务信息' : '查看任务信息')
              .fontSize(13).height(AppTheme.buttonHeight).backgroundColor(AppTheme.disabled).fontColor(AppTheme.secondary)
              .onClick(() => { this.showTechnicalDetails = !this.showTechnicalDetails; })
            if (this.showTechnicalDetails) this.TaskInfoCard()
          }
          .width('90%')
        }
        .layoutWeight(1)
        .align(Alignment.Top)
      }

      // 错误提示
      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor(AppTheme.danger)
          .width('90%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(AppTheme.dangerBackground)
          .borderRadius(AppTheme.buttonRadius)
          .margin({ bottom: 8 })

        Button('刷新任务状态')
          .width('90%')
          .height(AppTheme.buttonHeight)
          .fontSize(14)
          .backgroundColor(AppTheme.primary)
          .fontColor(AppTheme.surface)
          .borderRadius(AppTheme.buttonRadius)
          .margin({ bottom: 8 })
          .onClick(() => {
            this.fetchTask();
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background)
    .bindContentCover($$this.showLargePreview, this.LargePreview)
  }

  @Builder
  LargePreview() {
    Column() {
      Row() {
        Text('影像预览').fontSize(18).fontWeight(FontWeight.Bold)
        Blank()
        Button('关闭').height(AppTheme.buttonHeight).backgroundColor(AppTheme.primary).fontColor(AppTheme.surface).onClick(() => { this.showLargePreview = false; })
      }.width('100%').constraintSize({ minHeight: AppTheme.headerHeight }).flexShrink(0).padding(AppTheme.pagePadding)
      Stack() {
        Image(this.enlargedPreview).width('100%').height('100%').objectFit(ImageFit.Contain)
          .scale({ x: this.previewScale, y: this.previewScale })
          .gesture(PinchGesture()
            .onActionStart(() => { this.previewScaleBase = this.previewScale; })
            .onActionUpdate((event: GestureEvent) => {
              this.previewScale = Math.max(1, Math.min(5, this.previewScaleBase * event.scale));
            }))
      }.width('100%').layoutWeight(1).clip(true)
      Text('双指缩放，最多放大 5 倍').fontSize(13).fontColor(AppTheme.secondary).padding(AppTheme.pagePadding)
    }.width('100%').height('100%').padding({ top: this.topInset, bottom: this.bottomInset }).backgroundColor(AppTheme.surface)
  }

  @Builder
  ConsensusCard(consensus: ModelConsensus) {
    Column() {
      // 标题行 + 一致性标签
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Text('综合结果')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text)

        Blank()

        if (consensus.consistency) {
          Text(consensus.consistency === 'consistent' ? '两模型结果相互支持' : '两模型结果存在差异')
            .fontSize(12)
            .fontColor(consensus.consistency === 'consistent' ? AppTheme.success : AppTheme.warning)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(consensus.consistency === 'consistent' ? AppTheme.successBackground : '#fef3c7')
            .borderRadius(4)
        }

        if (consensus.requires_review) {
          Text('建议复核')
            .fontSize(12)
            .fontColor(AppTheme.warning)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#fef3c7')
            .borderRadius(4)
            .margin({ left: 4 })
        }
      }
      .width('100%')
      .margin({ bottom: 8 })

      // 主结果文字
      Text(this.conclusion(consensus))
        .fontSize(20).fontWeight(FontWeight.Bold).width('100%')
        .fontColor(this.getConsensusColor(this.getConsensusTone(consensus))).margin({ bottom: 8 })
      if (consensus.summary) {
        Text(consensus.summary)
          .fontSize(14)
          .fontColor(AppTheme.secondary)
          .width('100%')
          .margin({ bottom: 8 })
      }

      // 证据项
      if (consensus.primary_evidence) {
        Text(this.evidence(consensus))
          .fontSize(14)
          .fontColor(AppTheme.secondary)
          .width('100%')
          .margin({ bottom: 4 })
      }

      if (consensus.segmentation_detected !== undefined) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Text('分割结果: ')
            .fontSize(14)
            .fontColor(AppTheme.secondary)
          Text(consensus.segmentation_detected ? '检出区域' : '未检出区域')
            .fontSize(14)
            .fontColor(consensus.segmentation_detected ? AppTheme.danger : AppTheme.success)
            .fontWeight(FontWeight.Medium)
          if (validNumber(consensus.segmentation_volume_mm3)) {
            Text(` · ${this.measure(consensus.segmentation_volume_mm3)}`)
              .fontSize(14)
              .fontColor(AppTheme.secondary)
          }
          if (validNumber(consensus.segmentation_ratio) && consensus.segmentation_ratio! <= 1) {
            Text(` · 占比 ${formatProbability(consensus.segmentation_ratio)}`)
              .fontSize(14).fontColor(AppTheme.secondary)
          }
        }
        .width('100%')
        .margin({ bottom: 4 })
      }
    }
    .width('100%')
    .padding(AppTheme.pagePadding)
    .backgroundColor(this.getConsensusBgColor(this.getConsensusTone(consensus)))
    .borderRadius(AppTheme.cardRadius)
    .margin({ bottom: 12 })
  }

  @Builder
  ClassificationCard(classification: ClassificationResult) {
    Column() {
      Text('影像与模型依据')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text)
        .width('100%')
        .margin({ bottom: 12 })

      // 分类结论
      Text(classificationLabel(classification))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(classification.class === 'yes' ? AppTheme.danger : classification.class === 'no' ? AppTheme.success : AppTheme.secondary)
        .width('100%')
        .margin({ bottom: 8 })

      // 置信度
      Row() {
        Text('置信度: ')
          .fontSize(14)
          .fontColor(AppTheme.secondary)
        Text(formatProbability(classification.confidence))
          .fontSize(14)
          .fontColor(AppTheme.text)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .margin({ bottom: 8 })

      // 概率分布
      if (classification.probabilities) {
        Text('概率分布')
          .fontSize(14)
          .fontColor(AppTheme.secondary)
          .width('100%')
          .margin({ bottom: 4 })

        ForEach(Object.keys(classification.probabilities), (key: string) => {
          Row() {
            Text(`${key === 'yes' ? '异常' : key === 'no' ? '正常' : key}: `)
              .fontSize(12)
              .fontColor(AppTheme.secondary)
              .width(50)
            Progress({
              value: classification.probabilities[key] * 100,
              total: 100,
              type: ProgressType.Linear
            })
              .width('55%')
              .color(key === 'yes' ? AppTheme.danger : AppTheme.success)
              .backgroundColor('#e8eef7')
            Text(formatProbability(classification.probabilities[key]))
              .fontSize(12)
              .fontColor(AppTheme.text)
              .margin({ left: 8 })
          }
          .width('100%')
          .margin({ bottom: 4 })
        })
      }

      if (probabilitySeries(classification).length) ProbabilityChart({ classification: classification })

    }
    .width('100%')
    .padding(AppTheme.pagePadding)
    .backgroundColor(AppTheme.surface)
    .borderRadius(AppTheme.cardRadius)
    .margin({ bottom: 12 })
  }

  @Builder
  SegmentationCard(segmentation: SegmentationResult) {
    Column() {
      Text('影像学关键特征')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text)
        .width('100%')
        .margin({ bottom: 12 })

      Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.resultMetrics(), (metric: ResultMetric) => {
        Column() {
          Text(metric.label).fontSize(13).fontColor(AppTheme.secondary).width('100%')
          Text(metric.value).fontSize(18).fontWeight(FontWeight.Medium).fontColor(AppTheme.text).width('100%').margin({ top: 4 })
          if (metric.detail) Text(metric.detail).fontSize(12).fontColor(AppTheme.muted).width('100%')
          if (metric.meter !== undefined) Progress({ value: metric.meter, total: 100, type: ProgressType.Linear })
            .width('100%').color(AppTheme.primary).margin({ top: 8 })
        }.width(metric.key === 'extent' ? '100%' : '48%').padding(12).backgroundColor(AppTheme.subtle)
          .borderRadius(AppTheme.buttonRadius).margin({ right: metric.key === 'extent' ? 0 : '2%', bottom: 8 })
      }, (metric: ResultMetric) => `${metric.key}:${metric.value}`)
      }.width('100%')

      if (segmentation.regions) {
        Button(this.showRegionDetails ? '收起分割区域明细' : '展开分割区域明细').height(AppTheme.buttonHeight)
          .backgroundColor(AppTheme.surface).fontColor(AppTheme.primary).borderRadius(AppTheme.buttonRadius)
          .onClick(() => { this.showRegionDetails = !this.showRegionDetails; })
      }
      if (segmentation.regions && this.showRegionDetails) {
        ForEach(Object.keys(segmentation.regions), (key: string) => {
          Row() {
            Text(`${key} · ${this.getRegionName(key)}`)
              .fontSize(14)
              .fontColor(AppTheme.text)
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)

            Text(this.measure(segmentation.regions![key].volume_mm3))
              .fontSize(12)
              .fontColor(AppTheme.secondary)
          }
          .width('100%')
          .constraintSize({ minHeight: 44 })
          .padding(12)
          .borderRadius(AppTheme.buttonRadius)
          .backgroundColor(AppTheme.subtle)
          .border({ width: { left: 3 }, color: { left: this.getRegionColor(key) } })
          .margin({ bottom: 4 })
        })
      }

    }
    .width('100%')
    .padding(AppTheme.pagePadding)
    .backgroundColor(AppTheme.surface)
    .borderRadius(AppTheme.cardRadius)
    .margin({ bottom: 12 })
  }

  @Builder
  SupplementaryCard(supplementary: SupplementaryAnalysis) {
    Column() {
      Text('AI 辅助分析')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text)
        .width('100%')
        .margin({ bottom: 12 })

      if (supplementary.content) {
        if (supplementary.content.summary) {
          Text(`结论: ${supplementary.content.summary}`)
            .fontSize(14)
            .fontColor(AppTheme.text)
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .margin({ bottom: 8 })
        }

        if (supplementary.content.follow_up) {
          Text(`建议: ${supplementary.content.follow_up}`)
            .fontSize(14)
            .fontColor(AppTheme.primary)
            .width('100%')
            .margin({ bottom: 8 })
        }

        if (supplementary.content.uncertainties && supplementary.content.uncertainties.length > 0) {
          Text('不确定项:')
            .fontSize(14)
            .fontColor(AppTheme.secondary)
            .width('100%')
            .margin({ bottom: 4 })

          ForEach(supplementary.content.uncertainties, (item: string) => {
            Text(`· ${item}`)
              .fontSize(12)
              .fontColor(AppTheme.secondary)
              .width('100%')
              .margin({ bottom: 2 })
          })
        }

        if (supplementary.content.observations && supplementary.content.observations.length > 0) {
          Text('观察项:')
            .fontSize(14)
            .fontColor(AppTheme.secondary)
            .width('100%')
            .margin({ bottom: 4 })

          ForEach(supplementary.content.observations, (item: string) => {
            Text(`· ${item}`)
              .fontSize(12)
              .fontColor(AppTheme.secondary)
              .width('100%')
              .margin({ bottom: 2 })
          })
        }
      }
    }
    .width('100%')
    .padding(AppTheme.pagePadding)
    .backgroundColor(AppTheme.surface)
    .borderRadius(AppTheme.cardRadius)
    .margin({ bottom: 12 })
  }

  @Builder
  FollowUpCard() {
    Column() {
      Text('随访对比')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text)
        .width('100%')
        .margin({ bottom: 8 })

      Button('新增复查')
        .height(AppTheme.buttonHeight)
        .fontSize(13)
        .backgroundColor(AppTheme.disabled)
        .fontColor(AppTheme.primary)
        .onClick(() => { this.startFollowUp(); })
        .margin({ bottom: 10 })

      if (this.followUpLoading) {
        Text('正在读取同一病例的历史检查…')
          .fontSize(13)
          .fontColor(AppTheme.secondary)
          .width('100%')
      } else if (this.followUpError) {
        Text(this.followUpError)
          .fontSize(13)
          .fontColor(AppTheme.danger)
          .width('100%')
        Button('重试读取')
          .height(AppTheme.buttonHeight)
          .fontSize(12)
          .backgroundColor(AppTheme.disabled)
          .fontColor(AppTheme.primary)
          .margin({ top: 8 })
          .onClick(() => { this.loadFollowUp(this.taskId); })
      } else if (this.historyItems().length > 0) {
        Text(`${this.selectedFollowUpTaskId === this.followUp?.baseline?.task_id ? '默认上一期' : '已选择历史检查'} · ${this.date(this.selectedFollowUp()?.task.study_date || this.selectedFollowUp()?.task.created_at)} → 本次`)
          .fontSize(13).fontColor(AppTheme.secondary).width('100%').margin({ bottom: 8 })
        Button(`自由选择对比检查 · ${this.historyItems().length} 份历史检查`).height(AppTheme.buttonHeight)
          .fontSize(13).backgroundColor(AppTheme.subtle).fontColor(AppTheme.primary).borderRadius(AppTheme.buttonRadius)
          .onClick(() => { this.showFollowUpHistory = !this.showFollowUpHistory; }).margin({ bottom: 12 })
        if (this.showFollowUpHistory) {
        ForEach(this.historyItems(), (item: TaskFollowUpHistoryItem) => {
          Column() {
            Text(`${this.followUp?.baseline?.task_id === item.task.task_id ? '推荐基线 · ' : ''}${this.date(item.task.study_date || item.task.created_at)}`)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.text)
              .width('100%')
            Text(item.task.name || item.task.task_id)
              .fontSize(12)
              .fontColor(AppTheme.secondary)
              .width('100%')
          }
          .width('100%')
          .padding(10)
          .backgroundColor(this.selectedFollowUpTaskId === item.task.task_id ? AppTheme.selected : AppTheme.subtle)
          .borderRadius(AppTheme.buttonRadius)
          .margin({ bottom: 6 })
          .onClick(() => { this.selectedFollowUpTaskId = item.task.task_id; })
        }, (item: TaskFollowUpHistoryItem) => item.task.task_id)
        }

        if (this.followUpMetrics().length > 0) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.followUpMetrics(), (metric: FollowUpMetric) => {
            Column() {
              Text(metric.label)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.text)
                .width('100%')
              Text(metric.current).fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppTheme.primary).width('100%')
              Text(`基线 ${metric.baseline}`)
                .fontSize(13)
                .fontColor(AppTheme.secondary)
                .width('100%')
                .margin({ top: 4 })
              Text(`变化 ${metric.change}`)
                .fontSize(13)
                .fontColor(AppTheme.secondary)
                .width('100%')
                .margin({ top: 4 })
            }
            .width('48%')
            .padding(10)
            .backgroundColor(AppTheme.subtle)
            .borderRadius(AppTheme.buttonRadius)
            .margin({ top: 6 })
          }, (metric: FollowUpMetric) => `${metric.key}:${metric.baseline}:${metric.current}`)
          }.width('100%')
        } else {
          Text('当前与基线检查缺少可共同量化的结果。')
            .fontSize(13)
            .fontColor(AppTheme.secondary)
            .width('100%')
        }
      } else {
        Text('该病例暂无已完成的历史检查，上传复查后可在这里对比。')
          .fontSize(13)
          .fontColor(AppTheme.secondary)
          .width('100%')
      }
    }
    .width('100%')
    .padding(AppTheme.pagePadding)
    .backgroundColor(AppTheme.surface)
    .borderRadius(AppTheme.cardRadius)
    .margin({ bottom: 12 })
  }

  @Builder
  PreviewCard() {
    Column() {
      Text('切片预览').fontSize(16).fontWeight(FontWeight.Bold).fontColor(AppTheme.text).width('100%')
      Row({ space: 8 }) {
        Button('分割叠加').backgroundColor(this.previewMode === 'overlay' ? AppTheme.primary : AppTheme.disabled)
          .fontColor(this.previewMode === 'overlay' ? AppTheme.surface : AppTheme.secondary).height(AppTheme.buttonHeight).fontSize(13).borderRadius(AppTheme.buttonRadius)
          .onClick(() => { this.selectPreviewMode('overlay'); })
        Button('原始切片').backgroundColor(this.previewMode === 'raw' ? AppTheme.primary : AppTheme.disabled)
          .fontColor(this.previewMode === 'raw' ? AppTheme.surface : AppTheme.secondary).height(AppTheme.buttonHeight).fontSize(13).borderRadius(AppTheme.buttonRadius)
          .onClick(() => { this.selectPreviewMode('raw'); })
      }.width('100%').margin({ top: 12, bottom: 12 })
      if (this.previewFrames().length > 1) {
        Row() {
          Button('上一层').height(AppTheme.buttonHeight).fontSize(13).backgroundColor(AppTheme.surface).fontColor(AppTheme.primary)
            .enabled(this.previewIndex > 0).onClick(() => { this.previewIndex--; })
          Text(`${this.previewIndex + 1} / ${this.previewFrames().length}`).fontSize(13).fontColor(AppTheme.secondary).layoutWeight(1).textAlign(TextAlign.Center)
          Button('下一层').height(AppTheme.buttonHeight).fontSize(13).backgroundColor(AppTheme.surface).fontColor(AppTheme.primary)
            .enabled(this.previewIndex < this.previewFrames().length - 1).onClick(() => { this.previewIndex++; })
        }.width('100%')
      }
      ForEach(this.shownPreviews(), (item: PreviewImage) => {
        Column() {
          Text(item.label).fontSize(13).fontColor(AppTheme.secondary).width('100%')
          if (item.uri) {
            Image(item.uri).width('100%').objectFit(ImageFit.Contain).borderRadius(AppTheme.buttonRadius)
              .onClick(() => { this.enlargedPreview = item.uri; this.previewScale = 1; this.showLargePreview = true; })
          } else {
            Text(item.error ? '该张预览暂时无法加载' : '正在加载影像…')
              .fontSize(13).fontColor(AppTheme.muted).padding(24)
          }
        }.width('100%').margin({ bottom: 12 })
      }, (item: PreviewImage) => `${item.key}:${item.uri ? 'ready' : item.error ? 'error' : 'loading'}`)
      if (this.hasPreviewErrors()) {
        Button('重试缺失预览').height(AppTheme.buttonHeight).backgroundColor(AppTheme.disabled).fontColor(AppTheme.primary)
          .onClick(() => { if (this.task) this.loadPreviewImages(this.task); })
      }
    }.width('100%').padding(AppTheme.pagePadding).backgroundColor(AppTheme.surface).borderRadius(AppTheme.cardRadius).margin({ bottom: 12 })
  }

  @Builder
  TaskInfoCard() {
    Column() {
      Text('任务信息')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text)
        .width('100%')
        .margin({ bottom: 12 })

      Row() {
        Text('任务 ID: ')
          .fontSize(12)
          .fontColor(AppTheme.secondary)
          .width(80)
        Text(this.task!.task_id)
          .fontSize(12)
          .fontColor(AppTheme.text)
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 4 })

      if (this.task!.name) {
        Row() {
          Text('名称: ')
            .fontSize(12)
            .fontColor(AppTheme.secondary)
            .width(80)
          Text(this.task!.name)
            .fontSize(12)
            .fontColor(AppTheme.text)
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ bottom: 4 })
      }

      if (this.task!.case_id) {
        Row() {
          Text('病例 ID: ')
            .fontSize(12)
            .fontColor(AppTheme.secondary)
            .width(80)
          Text(this.task!.case_id)
            .fontSize(12)
            .fontColor(AppTheme.text)
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ bottom: 4 })
      }

      if (this.task!.study_date) {
        Row() {
          Text('检查日期: ')
            .fontSize(12)
            .fontColor(AppTheme.secondary)
            .width(80)
          Text(this.task!.study_date)
            .fontSize(12)
            .fontColor(AppTheme.text)
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ bottom: 4 })
      }

      Row() {
        Text('创建时间: ')
          .fontSize(12)
          .fontColor(AppTheme.secondary)
          .width(80)
        Text(this.date(this.task!.created_at))
          .fontSize(12)
          .fontColor(AppTheme.text)
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 4 })

      Row() {
        Text('完成模型: ')
          .fontSize(12)
          .fontColor(AppTheme.secondary)
          .width(80)
        Text(this.task!.completed_models.join(', '))
          .fontSize(12)
          .fontColor(AppTheme.text)
          .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppTheme.pagePadding)
    .backgroundColor(AppTheme.surface)
    .borderRadius(AppTheme.cardRadius)
    .margin({ bottom: 12 })
  }
}
