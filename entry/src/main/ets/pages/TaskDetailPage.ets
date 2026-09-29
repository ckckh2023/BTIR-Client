import { router } from '@kit.ArkUI';
import { TaskService } from '../service/TaskService';
import { ApiError } from '../common/ApiError';
import { TokenManager } from '../common/HttpClient';
import { buffer } from '@kit.ArkTS';
import {
  TaskStatusResponse,
  FrontendResult,
  ClassificationResult,
  SegmentationResult,
  ModelConsensus,
  ResultFiles,
  PreviewFrame,
} from '../model/TaskModels';

@Entry
@Component
struct TaskDetailPage {
  @State taskId: string = '';
  @State task: TaskStatusResponse | null = null;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State pollTimerId: number = -1;
  @State previewImageUris: Record<string, string> = {};
  @State isCancelling: boolean = false;
  @State isRetrying: boolean = false;

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

    if (resultFiles.preview) {
      try {
        const buffer = await this.taskService.downloadFile(task.task_id, resultFiles.preview);
        const base64 = this.arrayBufferToBase64(buffer);
        this.previewImageUris['preview'] = `data:image/png;base64,${base64}`;
      } catch (e) {
        // 预览图加载失败不影响主流程
      }
    }

    if (resultFiles.preview_series && resultFiles.preview_series.frames) {
      for (let i = 0; i < resultFiles.preview_series.frames.length; i++) {
        const frame = resultFiles.preview_series.frames[i];
        const overlayPath = frame.overlay;
        if (overlayPath) {
          try {
            const buffer = await this.taskService.downloadFile(task.task_id, overlayPath);
            const base64 = this.arrayBufferToBase64(buffer);
            this.previewImageUris[`frame_${i}_overlay`] = `data:image/png;base64,${base64}`;
          } catch (e) {
            // 忽略单帧加载失败
          }
        }
        const rawPath = frame.raw;
        if (rawPath) {
          try {
            const buffer = await this.taskService.downloadFile(task.task_id, rawPath);
            const base64 = this.arrayBufferToBase64(buffer);
            this.previewImageUris[`frame_${i}_raw`] = `data:image/png;base64,${base64}`;
          } catch (e) {
            // 忽略单帧加载失败
          }
        }
      }
    }
  }

  arrayBufferToBase64(bufferData: ArrayBuffer): string {
    const buf = buffer.from(bufferData);
    return buf.toString('base64');
  }

  getStatusColor(status: string): string {
    switch (status) {
      case 'succeeded':
        return '#4CAF50';
      case 'failed':
        return '#E53935';
      case 'canceled':
        return '#9E9E9E';
      case 'running':
        return '#1A73E8';
      case 'queued':
        return '#FF9800';
      case 'cancel_requested':
        return '#FF9800';
      case 'partial':
        return '#FF9800';
      default:
        return '#757575';
    }
  }

  getStatusText(status: string): string {
    switch (status) {
      case 'created':
        return '已创建';
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

  async handleCancel(): Promise<void> {
    this.isCancelling = true;
    try {
      await this.taskService.cancelTask(this.taskId);
      this.fetchTask();
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
      this.fetchTask();
    } catch (error) {
      this.errorMessage = `重试失败: ${error instanceof ApiError ? error.message : String(error)}`;
    } finally {
      this.isRetrying = false;
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Button('返回')
          .height(32)
          .fontSize(12)
          .backgroundColor('#757575')
          .onClick(() => {
            router.back();
          })

        Blank()

        Text('任务详情')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')

        Blank()

        Text(this.taskId)
          .fontSize(12)
          .fontColor('#999999')
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color('#1A73E8')
          Text('加载中...')
            .fontSize(14)
            .fontColor('#666666')
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
                  .fontColor('#333333')

                Blank()

                Text(this.getStatusText(this.task!.status))
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.getStatusColor(this.task!.status))
              }
              .width('100%')
              .margin({ bottom: 8 })

              // 进度条
              if (this.task!.status === 'running' || this.task!.status === 'queued' ||
                this.task!.status === 'cancel_requested') {
                if (this.task!.progress !== null && this.task!.progress !== undefined) {
                  Progress({ value: this.task!.progress, total: 100, type: ProgressType.Linear })
                    .width('100%')
                    .color('#1A73E8')
                    .margin({ bottom: 8 })
                }

                if (this.task!.progress_stage) {
                  Text(this.task!.progress_stage)
                    .fontSize(14)
                    .fontColor('#666666')
                    .width('100%')
                }

                // 取消按钮
                Button(this.isCancelling ? '取消中...' : '取消任务')
                  .width('100%')
                  .height(40)
                  .fontSize(14)
                  .backgroundColor('#E53935')
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
                  Text(`错误: ${this.task!.error.message}`)
                    .fontSize(14)
                    .fontColor('#E53935')
                    .width('100%')
                    .margin({ top: 8 })
                }

                Button(this.isRetrying ? '重试中...' : '重试任务')
                  .width('100%')
                  .height(40)
                  .fontSize(14)
                  .backgroundColor('#1A73E8')
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
            .backgroundColor('#FFFFFF')
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
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor('#E53935')
          .width('90%')
          .margin({ bottom: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }

  @Builder
  ConsensusCard(consensus: ModelConsensus) {
    Column() {
      Text('综合结果')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .width('100%')
        .margin({ bottom: 8 })

      if (consensus.summary) {
        Text(consensus.summary)
          .fontSize(14)
          .fontColor('#333333')
          .width('100%')
          .margin({ bottom: 8 })
      }

      if (consensus.requires_review) {
        Row() {
          Text('建议复核')
            .fontSize(12)
            .fontColor('#FF9800')
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')
      }

      if (consensus.consistency) {
        Row() {
          Text('一致性: ')
            .fontSize(12)
            .fontColor('#666666')
          Text(consensus.consistency)
            .fontSize(12)
            .fontColor('#333333')
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')
        .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  ClassificationCard(classification: ClassificationResult) {
    Column() {
      Text('分类结果')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .width('100%')
        .margin({ bottom: 12 })

      // 分类结论
      Row() {
        Text('结论: ')
          .fontSize(14)
          .fontColor('#666666')
        Text(classification.class === 'yes' ? '提示肿瘤相关异常' : '未发现明显异常')
          .fontSize(14)
          .fontColor(classification.class === 'yes' ? '#E53935' : '#4CAF50')
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .margin({ bottom: 8 })

      // 置信度
      Row() {
        Text('置信度: ')
          .fontSize(14)
          .fontColor('#666666')
        Text(`${(classification.confidence * 100).toFixed(1)}%`)
          .fontSize(14)
          .fontColor('#333333')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .margin({ bottom: 8 })

      // 概率分布
      if (classification.probabilities) {
        Text('概率分布')
          .fontSize(14)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })

        ForEach(Object.keys(classification.probabilities), (key: string) => {
          Row() {
            Text(`${key}: `)
              .fontSize(12)
              .fontColor('#666666')
              .width(60)
            Progress({
              value: classification.probabilities[key] * 100,
              total: 100,
              type: ProgressType.Linear
            })
              .width('60%')
              .color(key === 'yes' ? '#E53935' : '#4CAF50')
            Text(`${(classification.probabilities[key] * 100).toFixed(1)}%`)
              .fontSize(12)
              .fontColor('#333333')
              .margin({ left: 8 })
          }
          .width('100%')
          .margin({ bottom: 4 })
        })
      }

      // 实验性提示
      if (classification.experimental) {
        Text('此分类结果为实验性辅助分析，不作为确定诊断依据')
          .fontSize(12)
          .fontColor('#FF9800')
          .width('100%')
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  SegmentationCard(segmentation: SegmentationResult) {
    Column() {
      Text('分割结果')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .width('100%')
        .margin({ bottom: 12 })

      if (segmentation.regions) {
      if (segmentation.regions) {
        ForEach(Object.keys(segmentation.regions), (key: string) => {
          Row() {
            Text(segmentation.regions![key].name ?? key)
              .fontSize(14)
              .fontColor('#333333')
              .layoutWeight(1)

            if (segmentation.regions![key].volume_mm3) {
              Text(`${segmentation.regions![key].volume_mm3!.toFixed(1)} mm³`)
                .fontSize(12)
                .fontColor('#666666')
            }
          }
          .width('100%')
          .height(40)
          .padding({ left: 12, right: 12 })
          .borderRadius(8)
          .backgroundColor('#F5F5F5')
          .margin({ bottom: 4 })
        })
      }
      }

      if (segmentation.mask_file) {
        Row() {
          Text('分割掩码文件: ')
            .fontSize(12)
            .fontColor('#666666')
          Text(segmentation.mask_file)
            .fontSize(12)
            .fontColor('#1A73E8')
        }
        .width('100%')
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  SupplementaryCard(supplementary: Object) {
    Column() {
      Text('AI 辅助分析')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .width('100%')
        .margin({ bottom: 12 })

      if ((supplementary as Record<string, Object>)['content']) {
        if (((supplementary as Record<string, Object>)['content'] as Record<string, Object>)['summary']) {
          Row() {
            Text('结论: ')
              .fontSize(14)
              .fontColor('#666666')
            Text(((supplementary as Record<string, Object>)['content'] as Record<string, Object>)['summary'] as string)
              .fontSize(14)
              .fontColor('#333333')
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .margin({ bottom: 8 })
        }

        if (((supplementary as Record<string, Object>)['content'] as Record<string, Object>)['follow_up']) {
          Row() {
            Text('建议: ')
              .fontSize(14)
              .fontColor('#666666')
            Text(((supplementary as Record<string, Object>)['content'] as Record<string, Object>)['follow_up'] as string)
              .fontSize(14)
              .fontColor('#1A73E8')
          }
          .width('100%')
          .margin({ bottom: 8 })
        }

        if (((supplementary as Record<string, Object>)['content'] as Record<string, Object>)['uncertainties'] &&
          (((supplementary as Record<string, Object>)['content'] as Record<string, Object>)['uncertainties'] as string[]).length > 0) {
          Text('不确定项:')
            .fontSize(14)
            .fontColor('#666666')
            .width('100%')
            .margin({ bottom: 4 })

          ForEach(((supplementary as Record<string, Object>)['content'] as Record<string, Object>)['uncertainties'] as string[], (item: string) => {
            Text(`· ${item}`)
              .fontSize(12)
              .fontColor('#666666')
              .width('100%')
              .margin({ bottom: 2 })
          })
        }
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  PreviewCard() {
    Column() {
      Text('切片预览')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
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
              .fontColor('#666666')
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
        .fontColor('#999999')
        .width('100%')
        .margin({ top: 4 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  TaskInfoCard() {
    Column() {
      Text('任务信息')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .width('100%')
        .margin({ bottom: 12 })

      Row() {
        Text('任务 ID: ')
          .fontSize(12)
          .fontColor('#666666')
          .width(80)
        Text(this.task!.task_id)
          .fontSize(12)
          .fontColor('#333333')
      }
      .width('100%')
      .margin({ bottom: 4 })

      if (this.task!.name) {
        Row() {
          Text('名称: ')
            .fontSize(12)
            .fontColor('#666666')
            .width(80)
          Text(this.task!.name)
            .fontSize(12)
            .fontColor('#333333')
        }
        .width('100%')
        .margin({ bottom: 4 })
      }

      if (this.task!.case_id) {
        Row() {
          Text('病例 ID: ')
            .fontSize(12)
            .fontColor('#666666')
            .width(80)
          Text(this.task!.case_id)
            .fontSize(12)
            .fontColor('#333333')
        }
        .width('100%')
        .margin({ bottom: 4 })
      }

      if (this.task!.study_date) {
        Row() {
          Text('检查日期: ')
            .fontSize(12)
            .fontColor('#666666')
            .width(80)
          Text(this.task!.study_date)
            .fontSize(12)
            .fontColor('#333333')
        }
        .width('100%')
        .margin({ bottom: 4 })
      }

      Row() {
        Text('创建时间: ')
          .fontSize(12)
          .fontColor('#666666')
          .width(80)
        Text(this.task!.created_at)
          .fontSize(12)
          .fontColor('#333333')
      }
      .width('100%')
      .margin({ bottom: 4 })

      Row() {
        Text('完成模型: ')
          .fontSize(12)
          .fontColor('#666666')
          .width(80)
        Text(this.task!.completed_models.join(', '))
          .fontSize(12)
          .fontColor('#333333')
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 12 })
  }
}
