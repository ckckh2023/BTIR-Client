import { router } from '@kit.ArkUI';
import { TaskService } from '../service/TaskService';
import { ApiError } from '../common/ApiError';
import { TokenManager } from '../common/HttpClient';
import { buffer } from '@kit.ArkTS';
import {
  TaskStatusResponse,
  ClassificationResult,
  SegmentationResult,
  ModelConsensus,
  SupplementaryAnalysis,
} from '../model/TaskModels';

@Entry
@Component
struct TaskDetailPage {
  @State taskId: string = '';
  @State task: TaskStatusResponse | null = null;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  private pollTimerId: number = -1;
  @State previewImageUris: Record<string, string> = {};
  @State isCancelling: boolean = false;
  @State isRetrying: boolean = false;
  @State isStarting: boolean = false;

  private taskService: TaskService = new TaskService();

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params && params['taskId']) {
      this.taskId = params['taskId'];
      this.fetchTask();
    }
  }

  aboutToDisappear(): void {
    this.stopPolling();
  }

  startPolling(): void {
    this.stopPolling();
    this.pollTimerId = setInterval(() => {
      this.fetchTask();
    }, 3000);
  }

  stopPolling(): void {
    if (this.pollTimerId !== -1) {
      clearInterval(this.pollTimerId);
      this.pollTimerId = -1;
    }
  }

  isTerminalStatus(status: string): boolean {
    return ['succeeded', 'partial', 'failed', 'canceled'].includes(status);
  }

  async fetchTask(): Promise<void> {
    try {
      const response = await this.taskService.getTask(this.taskId);
      this.task = response;
      this.errorMessage = '';

      if (this.isTerminalStatus(response.status)) {
        this.stopPolling();
        if (response.status === 'succeeded' || response.status === 'partial') {
          this.loadPreviewImages(response);
        }
      } else if (this.pollTimerId === -1) {
        this.startPolling();
      }

      this.isLoading = false;
    } catch (error) {
      if (error instanceof ApiError && error.isTokenExpired()) {
        TokenManager.getInstance().clearAuth();
        router.replaceUrl({ url: 'pages/LoginPage' });
        return;
      }
      this.errorMessage = `获取任务信息失败: ${error instanceof ApiError ? error.message : String(error)}`;
      this.isLoading = false;
      this.stopPolling();
    }
  }

  async loadPreviewImages(task: TaskStatusResponse): Promise<void> {
    const frontendResult = task.frontend_result;
    if (!frontendResult || !frontendResult.result_files) {
      return;
    }

    const resultFiles = frontendResult.result_files;
    const newUris: Record<string, string> = {};

    if (resultFiles.preview) {
      try {
        const data = await this.taskService.downloadFile(task.task_id, resultFiles.preview);
        const base64 = this.arrayBufferToBase64(data);
        newUris['preview'] = `data:image/png;base64,${base64}`;
      } catch (e) {
      }
    }

    if (resultFiles.preview_series && resultFiles.preview_series.frames) {
      for (let i = 0; i < resultFiles.preview_series.frames.length; i++) {
        const frame = resultFiles.preview_series.frames[i];
        const overlayPath = frame.overlay;
        if (overlayPath) {
          try {
            const data = await this.taskService.downloadFile(task.task_id, overlayPath);
            const base64 = this.arrayBufferToBase64(data);
            newUris[`frame_${i}_overlay`] = `data:image/png;base64,${base64}`;
          } catch (e) {
          }
        }
        const rawPath = frame.raw;
        if (rawPath) {
          try {
            const data = await this.taskService.downloadFile(task.task_id, rawPath);
            const base64 = this.arrayBufferToBase64(data);
            newUris[`frame_${i}_raw`] = `data:image/png;base64,${base64}`;
          } catch (e) {
          }
        }
      }
    }

    this.previewImageUris = newUris;
  }

  arrayBufferToBase64(bufferData: ArrayBuffer): string {
    const buf = buffer.from(bufferData);
    return buf.toString('base64');
  }

  getStatusColor(status: string): string {
    switch (status) {
      case 'succeeded':
        return '#18794e';
      case 'failed':
        return '#b42318';
      case 'canceled':
        return '#586b82';
      case 'running':
        return '#1d4ed8';
      case 'queued':
        return '#1d4ed8';
      case 'cancel_requested':
        return '#1d4ed8';
      case 'partial':
        return '#586b82';
      default:
        return '#586b82';
    }
  }

  getStatusText(status: string): string {
    switch (status) {
      case 'created':
        return '待运行';
      case 'queued':
        return '排队中';
      case 'running':
        return '运行中';
      case 'cancel_requested':
        return '取消中';
      case 'partial':
        return '部分完成';
      case 'succeeded':
        return '已完成';
      case 'failed':
        return '失败';
      case 'canceled':
        return '已取消';
      default:
        return status;
    }
  }

  getStatusBgColor(status: string): string {
    switch (status) {
      case 'succeeded':
        return '#dcfce7';
      case 'failed':
        return '#fee2e2';
      case 'canceled':
        return '#e6edf5';
      case 'running':
        return '#dbeafe';
      case 'queued':
        return '#dbeafe';
      case 'cancel_requested':
        return '#dbeafe';
      case 'partial':
        return '#e6edf5';
      default:
        return '#e6edf5';
    }
  }

  getPhaseColor(index: number, progress: number): string {
    const thresholds = [30, 55, 90];
    if (progress >= thresholds[index]) {
      return '#18794e';
    }
    if (index === 0 || progress >= thresholds[index - 1]) {
      return '#1d4ed8';
    }
    return '#7d90a8';
  }

  getPhaseBgColor(index: number, progress: number): string {
    const thresholds = [30, 55, 90];
    if (progress >= thresholds[index]) {
      return '#dcfce7';
    }
    if (index === 0 || progress >= thresholds[index - 1]) {
      return '#dbeafe';
    }
    return '#e6edf5';
  }

  getConsensusTone(consensus: ModelConsensus): string {
    if (consensus.requires_review) {
      return 'review';
    }
    if (consensus.summary) {
      const summary = consensus.summary.toLowerCase();
      if (summary.includes('高概率') && summary.includes('存在')) {
        return 'present';
      }
      if (summary.includes('倾向') && summary.includes('不存在')) {
        return 'absent';
      }
      if (summary.includes('高概率') && summary.includes('不存在')) {
        return 'absent';
      }
      if (summary.includes('可能') && summary.includes('存在')) {
        return 'possible';
      }
    }
    return 'review';
  }

  getConsensusColor(tone: string): string {
    switch (tone) {
      case 'present':
        return '#b42318';
      case 'absent':
        return '#18794e';
      case 'possible':
        return '#b7791f';
      case 'review':
        return '#b7791f';
      default:
        return '#1e2d3e';
    }
  }

  getConsensusBgColor(tone: string): string {
    switch (tone) {
      case 'present':
        return '#fff4f4';
      case 'absent':
        return '#f0fdf4';
      case 'possible':
        return '#fffbeb';
      case 'review':
        return '#fffbeb';
      default:
        return '#ffffff';
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
    this.isRetrying = true;
    try {
      await this.taskService.retryTask(this.taskId);
      await this.fetchTask();
    } catch (error) {
      this.errorMessage = `重试失败: ${error instanceof ApiError ? error.message : String(error)}`;
    } finally {
      this.isRetrying = false;
    }
  }

  async handleStart(): Promise<void> {
    this.isStarting = true;
    this.errorMessage = '';
    try {
      await this.taskService.runAsync(this.taskId);
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
      Row() {
        Button('返回')
          .height(32)
          .fontSize(12)
          .backgroundColor('#586b82')
          .fontColor('#ffffff')
          .borderRadius(6)
          .onClick(() => {
            router.back();
          })

        Blank()

        Text('任务详情')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1e2d3e')

        Blank()

        Text(this.taskId)
          .fontSize(12)
          .fontColor('#7d90a8')
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#ffffff')

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color('#1f477d')
          Text('加载中...')
            .fontSize(14)
            .fontColor('#586b82')
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
                Text('状态')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1e2d3e')

                Blank()

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

              if (this.task!.status === 'created') {
                Text('病例已上传，等待启动分析')
                  .fontSize(14)
                  .fontColor('#586b82')
                  .width('100%')
                  .margin({ bottom: 8 })

                Button(this.isStarting ? '启动中...' : '启动分析')
                  .width('100%')
                  .height(40)
                  .fontSize(14)
                  .backgroundColor('#1f477d')
                  .fontColor('#ffffff')
                  .borderRadius(8)
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
                        .fontColor(this.getPhaseColor(index, this.task!.progress ?? 0))
                    }
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .borderRadius(12)
                    .backgroundColor(this.getPhaseBgColor(index, this.task!.progress ?? 0))
                    .margin({ right: 8 })
                  })
                }
                .width('100%')
                .margin({ bottom: 8 })

                if (this.task!.progress !== null && this.task!.progress !== undefined) {
                  Progress({ value: this.task!.progress, total: 100, type: ProgressType.Linear })
                    .width('100%')
                    .color('#1f477d')
                    .backgroundColor('#e8eef7')
                    .margin({ bottom: 8 })
                }

                if (this.task!.progress_stage) {
                  Text(this.task!.progress_stage)
                    .fontSize(14)
                    .fontColor('#586b82')
                    .width('100%')
                }

                // 取消按钮
                Button(this.isCancelling ? '取消中...' : '取消任务')
                  .width('100%')
                  .height(40)
                  .fontSize(14)
                  .backgroundColor('#b42318')
                  .fontColor('#ffffff')
                  .borderRadius(8)
                  .enabled(!this.isCancelling && this.task!.status !== 'cancel_requested')
                  .margin({ top: 12 })
                  .onClick(() => {
                    this.handleCancel();
                  })
              }

              // 失败/取消状态操作
              if (this.task!.status === 'failed' || this.task!.status === 'canceled') {
                if (this.task!.error) {
                  Row() {
                    Text(`错误: ${this.task!.error.message}`)
                      .fontSize(14)
                      .fontColor('#b42318')
                  }
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor('#fee2e2')
                  .borderRadius(8)
                  .margin({ top: 8 })
                }

                Button(this.isRetrying ? '重试中...' : '重试任务')
                  .width('100%')
                  .height(40)
                  .fontSize(14)
                  .backgroundColor('#1f477d')
                  .fontColor('#ffffff')
                  .borderRadius(8)
                  .enabled(!this.isRetrying)
                  .margin({ top: 12 })
                  .onClick(() => {
                    this.handleRetry();
                  })
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#ffffff')
            .borderRadius(12)
            .margin({ bottom: 12 })

            // 综合结果
            if (this.task!.frontend_result?.model_consensus) {
              this.ConsensusCard(this.task!.frontend_result.model_consensus)
            }

            // 分类结果
            if (this.task!.frontend_result?.classification) {
              this.ClassificationCard(this.task!.frontend_result.classification)
            }

            // 分割结果
            if (this.task!.frontend_result?.segmentation) {
              this.SegmentationCard(this.task!.frontend_result.segmentation)
            }

            // AI 辅助分析
            if (this.task!.frontend_result?.supplementary_analysis?.content) {
              this.SupplementaryCard(this.task!.frontend_result.supplementary_analysis)
            }

            // 预览图片
            if (Object.keys(this.previewImageUris).length > 0) {
              this.PreviewCard()
            }

            // 任务信息
            this.TaskInfoCard()
          }
          .width('90%')
        }
        .layoutWeight(1)
      }

      // 错误提示
      if (this.errorMessage) {
        Row() {
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor('#b42318')
        }
        .width('90%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor('#fee2e2')
        .borderRadius(8)
        .margin({ bottom: 8 })

        Button('刷新任务状态')
          .width('90%')
          .height(36)
          .fontSize(14)
          .backgroundColor('#1f477d')
          .fontColor('#ffffff')
          .borderRadius(8)
          .margin({ bottom: 8 })
          .onClick(() => {
            this.fetchTask();
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f2f5f9')
  }

  @Builder
  ConsensusCard(consensus: ModelConsensus) {
    Column() {
      // 标题行 + 一致性标签
      Row() {
        Text('综合结果')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1e2d3e')

        Blank()

        if (consensus.consistency) {
          Text(consensus.consistency === 'consistent' ? '两模型结果相互支持' : '两模型结果存在差异')
            .fontSize(12)
            .fontColor(consensus.consistency === 'consistent' ? '#18794e' : '#b7791f')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(consensus.consistency === 'consistent' ? '#dcfce7' : '#fef3c7')
            .borderRadius(4)
        }

        if (consensus.requires_review) {
          Text('建议复核')
            .fontSize(12)
            .fontColor('#b7791f')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#fef3c7')
            .borderRadius(4)
            .margin({ left: 4 })
        }
      }
      .width('100%')
      .margin({ bottom: 8 })

      // 主结果文字
      if (consensus.summary) {
        Text(consensus.summary)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getConsensusColor(this.getConsensusTone(consensus)))
          .width('100%')
          .margin({ bottom: 8 })
      }

      // 证据项
      if (consensus.primary_evidence) {
        Text(consensus.primary_evidence)
          .fontSize(14)
          .fontColor('#586b82')
          .width('100%')
          .margin({ bottom: 4 })
      }

      if (consensus.segmentation_detected !== undefined) {
        Row() {
          Text('分割结果: ')
            .fontSize(14)
            .fontColor('#586b82')
          Text(consensus.segmentation_detected ? '检出区域' : '未检出区域')
            .fontSize(14)
            .fontColor(consensus.segmentation_detected ? '#b42318' : '#18794e')
            .fontWeight(FontWeight.Medium)
          if (consensus.segmentation_detected && consensus.segmentation_volume_mm3) {
            Text(` · ${consensus.segmentation_volume_mm3!.toFixed(1)} mm³`)
              .fontSize(14)
              .fontColor('#586b82')
          }
        }
        .width('100%')
        .margin({ bottom: 4 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getConsensusBgColor(this.getConsensusTone(consensus)))
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  ClassificationCard(classification: ClassificationResult) {
    Column() {
      Text('分类结论')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1e2d3e')
        .width('100%')
        .margin({ bottom: 12 })

      // 分类结论
      Row() {
        Text(classification.class === 'yes' ? '提示肿瘤相关异常' : '未发现明显异常')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(classification.class === 'yes' ? '#b42318' : '#18794e')
      }
      .width('100%')
      .margin({ bottom: 8 })

      // 置信度
      Row() {
        Text('置信度: ')
          .fontSize(14)
          .fontColor('#586b82')
        Text(`${(classification.confidence * 100).toFixed(1)}%`)
          .fontSize(14)
          .fontColor('#1e2d3e')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .margin({ bottom: 8 })

      // 概率分布
      if (classification.probabilities) {
        Text('概率分布')
          .fontSize(14)
          .fontColor('#586b82')
          .width('100%')
          .margin({ bottom: 4 })

        ForEach(Object.keys(classification.probabilities), (key: string) => {
          Row() {
            Text(`${key === 'yes' ? '异常' : '正常'}: `)
              .fontSize(12)
              .fontColor('#586b82')
              .width(50)
            Progress({
              value: classification.probabilities[key] * 100,
              total: 100,
              type: ProgressType.Linear
            })
              .width('55%')
              .color(key === 'yes' ? '#b42318' : '#18794e')
              .backgroundColor('#e8eef7')
            Text(`${(classification.probabilities[key] * 100).toFixed(1)}%`)
              .fontSize(12)
              .fontColor('#1e2d3e')
              .margin({ left: 8 })
          }
          .width('100%')
          .margin({ bottom: 4 })
        })
      }

      // 实验性提示
      if (classification.experimental) {
        Row() {
          Text('此分类结果为实验性辅助分析，不作为确定诊断依据')
            .fontSize(12)
            .fontColor('#b45309')
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('#fef3c7')
        .borderRadius(6)
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#ffffff')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  SegmentationCard(segmentation: SegmentationResult) {
    Column() {
      Text('分割结果')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1e2d3e')
        .width('100%')
        .margin({ bottom: 12 })

      if (segmentation.regions) {
        ForEach(Object.keys(segmentation.regions), (key: string) => {
          Row() {
            Text(`${key} · ${this.getRegionName(key)}`)
              .fontSize(14)
              .fontColor('#1e2d3e')
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)

            if (segmentation.regions![key].volume_mm3) {
              Text(`${segmentation.regions![key].volume_mm3!.toFixed(1)} mm³`)
                .fontSize(12)
                .fontColor('#586b82')
            }
          }
          .width('100%')
          .height(40)
          .padding({ left: 12, right: 12 })
          .borderRadius(8)
          .backgroundColor('#f7f9fc')
          .border({ width: { left: 3 }, color: { left: this.getRegionColor(key) } })
          .margin({ bottom: 4 })
        })
      }

      if (segmentation.mask_file) {
        Row() {
          Text('分割掩码文件: ')
            .fontSize(12)
            .fontColor('#586b82')
          Text(segmentation.mask_file)
            .fontSize(12)
            .fontColor('#1f477d')
        }
        .width('100%')
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#ffffff')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  SupplementaryCard(supplementary: SupplementaryAnalysis) {
    Column() {
      Text('AI 辅助分析')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1e2d3e')
        .width('100%')
        .margin({ bottom: 12 })

      if (supplementary.content) {
        if (supplementary.content.summary) {
          Row() {
            Text('结论: ')
              .fontSize(14)
              .fontColor('#586b82')
            Text(supplementary.content.summary)
              .fontSize(14)
              .fontColor('#1e2d3e')
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .margin({ bottom: 8 })
        }

        if (supplementary.content.follow_up) {
          Row() {
            Text('建议: ')
              .fontSize(14)
              .fontColor('#586b82')
            Text(supplementary.content.follow_up)
              .fontSize(14)
              .fontColor('#1f477d')
          }
          .width('100%')
          .margin({ bottom: 8 })
        }

        if (supplementary.content.uncertainties && supplementary.content.uncertainties.length > 0) {
          Text('不确定项:')
            .fontSize(14)
            .fontColor('#586b82')
            .width('100%')
            .margin({ bottom: 4 })

          ForEach(supplementary.content.uncertainties, (item: string) => {
            Text(`· ${item}`)
              .fontSize(12)
              .fontColor('#586b82')
              .width('100%')
              .margin({ bottom: 2 })
          })
        }

        if (supplementary.content.observations && supplementary.content.observations.length > 0) {
          Text('观察项:')
            .fontSize(14)
            .fontColor('#586b82')
            .width('100%')
            .margin({ bottom: 4 })

          ForEach(supplementary.content.observations, (item: string) => {
            Text(`· ${item}`)
              .fontSize(12)
              .fontColor('#586b82')
              .width('100%')
              .margin({ bottom: 2 })
          })
        }
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#ffffff')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  PreviewCard() {
    Column() {
      Text('切片预览')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1e2d3e')
        .width('100%')
        .margin({ bottom: 12 })

      // 主预览图
      if (this.previewImageUris['preview']) {
        Image(this.previewImageUris['preview'])
          .width('100%')
          .objectFit(ImageFit.Contain)
          .borderRadius(8)
          .margin({ bottom: 8 })
      }

      // 预览序列帧
      ForEach(Object.keys(this.previewImageUris).filter(key => key.startsWith('frame_')), (key: string) => {
        if (key.endsWith('_overlay')) {
          Column() {
            Text(key.replace('frame_', '切片 ').replace('_overlay', ''))
              .fontSize(12)
              .fontColor('#586b82')
              .margin({ bottom: 4 })

            Image(this.previewImageUris[key])
              .width('100%')
              .objectFit(ImageFit.Contain)
              .borderRadius(8)
              .margin({ bottom: 4 })
          }
        } else if (key.endsWith('_raw')) {
          Column() {
            Text(key.replace('frame_', '切片 ').replace('_raw', ' (原始)'))
              .fontSize(12)
              .fontColor('#586b82')
              .margin({ bottom: 4 })

            Image(this.previewImageUris[key])
              .width('100%')
              .objectFit(ImageFit.Contain)
              .borderRadius(8)
              .margin({ bottom: 8 })
          }
        }
      })

      Text('注: 当前仅提供重点层及邻近层预览，非完整3D浏览')
        .fontSize(12)
        .fontColor('#7d90a8')
        .width('100%')
        .margin({ top: 4 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#ffffff')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  TaskInfoCard() {
    Column() {
      Text('任务信息')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1e2d3e')
        .width('100%')
        .margin({ bottom: 12 })

      Row() {
        Text('任务 ID: ')
          .fontSize(12)
          .fontColor('#586b82')
          .width(80)
        Text(this.task!.task_id)
          .fontSize(12)
          .fontColor('#1e2d3e')
      }
      .width('100%')
      .margin({ bottom: 4 })

      if (this.task!.name) {
        Row() {
          Text('名称: ')
            .fontSize(12)
            .fontColor('#586b82')
            .width(80)
          Text(this.task!.name)
            .fontSize(12)
            .fontColor('#1e2d3e')
        }
        .width('100%')
        .margin({ bottom: 4 })
      }

      if (this.task!.case_id) {
        Row() {
          Text('病例 ID: ')
            .fontSize(12)
            .fontColor('#586b82')
            .width(80)
          Text(this.task!.case_id)
            .fontSize(12)
            .fontColor('#1e2d3e')
        }
        .width('100%')
        .margin({ bottom: 4 })
      }

      if (this.task!.study_date) {
        Row() {
          Text('检查日期: ')
            .fontSize(12)
            .fontColor('#586b82')
            .width(80)
          Text(this.task!.study_date)
            .fontSize(12)
            .fontColor('#1e2d3e')
        }
        .width('100%')
        .margin({ bottom: 4 })
      }

      Row() {
        Text('创建时间: ')
          .fontSize(12)
          .fontColor('#586b82')
          .width(80)
        Text(this.task!.created_at)
          .fontSize(12)
          .fontColor('#1e2d3e')
      }
      .width('100%')
      .margin({ bottom: 4 })

      Row() {
        Text('完成模型: ')
          .fontSize(12)
          .fontColor('#586b82')
          .width(80)
        Text(this.task!.completed_models.join(', '))
          .fontSize(12)
          .fontColor('#1e2d3e')
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#ffffff')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }
}
