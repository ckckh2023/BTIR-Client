import { router } from '@kit.ArkUI';
import { TaskService } from '../service/TaskService';
import { ApiError } from '../common/ApiError';
import { ModalityCandidate, ModalitySelectionDetail } from '../model/TaskModels';

interface ModalitySelectionParam {
  modalities: string;
  code: string;
  archiveUri: string;
  taskName: string;
  caseId: string;
  caseName: string;
  studyDate: string;
}

@Entry
@Component
struct ModalitySelectPage {
  @State modalities: Record<string, ModalitySelectionDetail> = {};
  @State selectionCode: string = '';
  @State archiveUri: string = '';
  @State taskName: string = '';
  @State caseId: string = '';
  @State caseName: string = '';
  @State studyDate: string = '';
  @State selectedEntries: Record<string, string> = {};
  @State selectedSeriesUids: Record<string, string> = {};
  @State isLoading: boolean = false;
  @State errorMessage: string = '';

  private taskService: TaskService = new TaskService();

  aboutToAppear(): void {
    const params = router.getParams() as ModalitySelectionParam;
    if (params) {
      this.selectionCode = params.code;
      this.archiveUri = params.archiveUri;
      this.taskName = params.taskName;
      this.caseId = params.caseId;
      this.caseName = params.caseName;
      this.studyDate = params.studyDate;
      try {
        this.modalities = JSON.parse(params.modalities) as Record<string, ModalitySelectionDetail>;
      } catch (e) {
        this.errorMessage = '解析模态选择数据失败';
      }
    }
  }

  isNiftiMode(): boolean {
    return this.selectionCode === 'archive_modality_selection_required';
  }

  isDicomMode(): boolean {
    return this.selectionCode === 'dicom_series_selection_required';
  }

  async handleResubmit(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';

    try {
      const modalityEntries = this.isNiftiMode() ? this.selectedEntries : undefined;
      const modalitySeriesUids = this.isDicomMode() ? this.selectedSeriesUids : undefined;

      const response = await this.taskService.uploadArchive(
        this.archiveUri,
        this.taskName || undefined,
        this.caseId || undefined,
        this.caseName || undefined,
        this.studyDate || undefined,
        modalityEntries,
        modalitySeriesUids
      );

      await this.taskService.runAsync(response.task_id);

      router.replaceUrl({
        url: 'pages/TaskDetailPage',
        params: { taskId: response.task_id }
      });
    } catch (error) {
      if (error instanceof ApiError) {
        if (error.isModalitySelection()) {
          this.errorMessage = '仍有模态需要选择，请检查';
        } else {
          this.errorMessage = error.message;
        }
      } else {
        this.errorMessage = `提交失败: ${String(error)}`;
      }
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('模态选择')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')

        Blank()

        Button('返回')
          .height(32)
          .fontSize(12)
          .backgroundColor('#757575')
          .onClick(() => {
            router.back();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')

      // 说明
      Text(this.isNiftiMode() ?
        'ZIP 内模态文件需要确认，请为每个模态选择生效文件' :
        '检测到多个 DICOM 序列，请为每个模态选择生效序列')
        .fontSize(14)
        .fontColor('#666666')
        .width('90%')
        .margin({ top: 16, bottom: 16 })

      // 模态选择列表
      Scroll() {
        Column() {
          ForEach(Object.keys(this.modalities), (modalityKey: string) => {
            Column() {
              // 模态标题
              Row() {
                Text(modalityKey.toUpperCase())
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#333333')

                Blank()

                Text(this.modalities[modalityKey].reason ?? '')
                  .fontSize(12)
                  .fontColor('#E53935')
              }
              .width('100%')
              .margin({ bottom: 8 })

              if (this.modalities[modalityKey].message) {
                Text(this.modalities[modalityKey].message)
                  .fontSize(12)
                  .fontColor('#666666')
                  .width('100%')
                  .margin({ bottom: 8 })
              }

              // 候选项列表
              if (this.isNiftiMode()) {
                ForEach(this.modalities[modalityKey].candidates ?? [], (candidate: ModalityCandidate) => {
                  Row() {
                    Radio({ value: candidate.filename ?? '', group: modalityKey })
                      .onChange((isChecked: boolean) => {
                        if (isChecked && candidate.filename) {
                          this.selectedEntries[`${modalityKey}_entry`] = candidate.filename;
                        }
                      })
                      .margin({ right: 8 })

                    Column() {
                      Text(candidate.filename ?? '')
                        .fontSize(14)
                        .fontColor('#333333')
                      if (candidate.size_bytes) {
                        Text(`${(candidate.size_bytes / 1024 / 1024).toFixed(2)} MB`)
                          .fontSize(12)
                          .fontColor('#999999')
                      }
                    }
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .height(48)
                  .padding({ left: 12, right: 12 })
                })
              }

              if (this.isDicomMode()) {
                ForEach(this.modalities[modalityKey].candidates ?? [], (candidate: ModalityCandidate) => {
                  Row() {
                    Radio({ value: candidate.series_uid ?? '', group: modalityKey })
                      .onChange((isChecked: boolean) => {
                        if (isChecked && candidate.series_uid) {
                          this.selectedSeriesUids[`${modalityKey}_series_uid`] = candidate.series_uid;
                        }
                      })
                      .margin({ right: 8 })

                    Column() {
                      Text(candidate.label ?? candidate.series_uid ?? '')
                        .fontSize(14)
                        .fontColor('#333333')
                      if (candidate.file_count) {
                        Text(`${candidate.file_count} 个文件`)
                          .fontSize(12)
                          .fontColor('#999999')
                      }
                    }
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .height(48)
                  .padding({ left: 12, right: 12 })
                })
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .margin({ bottom: 12 })
          })
        }
        .width('90%')
      }
      .layoutWeight(1)

      // 错误提示
      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor('#E53935')
          .width('90%')
          .margin({ bottom: 8 })
      }

      // 确认按钮
      Button(this.isLoading ? '提交中...' : '确认选择并上传')
        .width('90%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .backgroundColor('#1A73E8')
        .borderRadius(8)
        .enabled(!this.isLoading)
        .margin({ bottom: 16 })
        .onClick(() => {
          this.handleResubmit();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}
