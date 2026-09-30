import { router } from '@kit.ArkUI';
import { TaskService, UploadArchiveOptions } from '../service/TaskService';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { ApiError } from '../common/ApiError';
import { ModalityCandidate, ModalitySelectionDetail } from '../model/TaskModels';

interface ModalitySelectionParam {
  modalities: string;
  code: string;
  archiveUri: string;
  archiveName: string;
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
  @State archiveName: string = '';
  @State taskName: string = '';
  @State caseId: string = '';
  @State caseName: string = '';
  @State studyDate: string = '';
  @State selectedEntries: Record<string, string> = {};
  @State selectedSeriesUids: Record<string, string> = {};
  @State replacementFiles: Record<string, string> = {};
  @State replacementNames: Record<string, string> = {};
  @State isLoading: boolean = false;
  @State uploadStage: string = '';
  @State errorMessage: string = '';

  private taskService: TaskService = new TaskService();

  aboutToAppear(): void {
    const params = router.getParams() as ModalitySelectionParam;
    if (params) {
      this.selectionCode = params.code;
      this.archiveUri = params.archiveUri;
      this.archiveName = params.archiveName || 'archive.zip';
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

  async selectReplacement(modality: string): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.nii', '.nii.gz'];
      const documentPicker = new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext);
      const uris = await documentPicker.select(options);
      if (uris && uris.length > 0) {
        const files: Record<string, string> = {};
        for (const key of Object.keys(this.replacementFiles)) {
          files[key] = this.replacementFiles[key];
        }
        files[modality] = uris[0];
        this.replacementFiles = files;
        const path = uris[0].split('?')[0];
        const encodedName = path.substring(path.lastIndexOf('/') + 1);
        try {
          const names: Record<string, string> = {};
          for (const key of Object.keys(this.replacementNames)) {
            names[key] = this.replacementNames[key];
          }
          names[modality] = decodeURIComponent(encodedName);
          this.replacementNames = names;
        } catch (error) {
          const names: Record<string, string> = {};
          for (const key of Object.keys(this.replacementNames)) {
            names[key] = this.replacementNames[key];
          }
          names[modality] = encodedName;
          this.replacementNames = names;
        }
        this.errorMessage = '';
      }
    } catch (error) {
      this.errorMessage = `选择文件失败：${String(error)}`;
    }
  }

  async handleResubmit(): Promise<void> {
    for (const modality of Object.keys(this.modalities)) {
      if (!this.replacementFiles[modality] && !this.selectedEntries[`${modality}_entry`] &&
        !this.selectedSeriesUids[`${modality}_series_uid`]) {
        this.errorMessage = `请确认 ${modality.toUpperCase()} 的文件或序列`;
        return;
      }
    }
    this.isLoading = true;
    this.errorMessage = '';

    try {
      const modalityEntries = this.isNiftiMode() ? this.selectedEntries : undefined;
      const modalitySeriesUids = this.isDicomMode() ? this.selectedSeriesUids : undefined;

      const options: UploadArchiveOptions = {
        name: this.taskName || undefined,
        caseId: this.caseId || undefined,
        caseName: this.caseName || undefined,
        studyDate: this.studyDate || undefined,
        modalityEntries: modalityEntries,
        modalitySeriesUids: modalitySeriesUids,
        replacementFiles: this.replacementFiles,
        replacementNames: this.replacementNames,
        onStage: (stage: string) => { this.uploadStage = stage; }
      };
      const response = await this.taskService.uploadArchive(
        this.archiveUri, (getContext(this) as common.UIAbilityContext).cacheDir, this.archiveName, options
      );

      this.uploadStage = '任务已创建，正在启动分析…';
      try {
        await this.taskService.runAsync(response.task_id);
      } catch (error) {
        // 详情页会查询实际状态，必要时允许重试启动。
      }

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
      this.uploadStage = '';
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('模态选择')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1e2d3e')

        Blank()

        Button('返回')
          .height(32)
          .fontSize(12)
          .backgroundColor('#586b82')
          .fontColor('#ffffff')
          .borderRadius(6)
          .onClick(() => {
            router.back();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#ffffff')

      // 说明
      Text(this.isNiftiMode() ?
        '请确认 ZIP 内的模态文件；缺失时可从手机补选 NIfTI 文件' :
        '请确认 DICOM 序列；缺失时可从手机补选 NIfTI 文件')
        .fontSize(14)
        .fontColor('#586b82')
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
                  .fontColor('#1e2d3e')

                Blank()

                Text(this.modalities[modalityKey].reason ?? '')
                  .fontSize(12)
                  .fontColor('#b42318')
              }
              .width('100%')
              .margin({ bottom: 8 })

              if (this.modalities[modalityKey].message) {
                Text(this.modalities[modalityKey].message)
                  .fontSize(12)
                  .fontColor('#586b82')
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
                          const newEntries: Record<string, string> = {};
                          for (const key of Object.keys(this.selectedEntries)) {
                            newEntries[key] = this.selectedEntries[key];
                          }
                          newEntries[`${modalityKey}_entry`] = candidate.filename;
                          this.selectedEntries = newEntries;
                        }
                      })
                      .margin({ right: 8 })

                    Column() {
                      Text(candidate.filename ?? '')
                        .fontSize(14)
                        .fontColor('#1e2d3e')
                      if (candidate.size_bytes) {
                        Text(`${(candidate.size_bytes / 1024 / 1024).toFixed(2)} MB`)
                          .fontSize(12)
                          .fontColor('#7d90a8')
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
                          const newUids: Record<string, string> = {};
                          for (const key of Object.keys(this.selectedSeriesUids)) {
                            newUids[key] = this.selectedSeriesUids[key];
                          }
                          newUids[`${modalityKey}_series_uid`] = candidate.series_uid;
                          this.selectedSeriesUids = newUids;
                        }
                      })
                      .margin({ right: 8 })

                    Column() {
                      Text(candidate.label ?? candidate.series_uid ?? '')
                        .fontSize(14)
                        .fontColor('#1e2d3e')
                      if (candidate.file_count) {
                        Text(`${candidate.file_count} 个文件`)
                          .fontSize(12)
                          .fontColor('#7d90a8')
                      }
                    }
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .height(48)
                  .padding({ left: 12, right: 12 })
                })
              }

              Button(this.replacementNames[modalityKey] ? '更换补选文件' : '从手机补选 NIfTI 文件')
                .width('100%')
                .height(40)
                .fontSize(13)
                .backgroundColor('#eaf2fb')
                .fontColor('#1f477d')
                .borderRadius(8)
                .enabled(!this.isLoading)
                .onClick(() => {
                  this.selectReplacement(modalityKey);
                })

              if (this.replacementNames[modalityKey]) {
                Text(this.replacementNames[modalityKey])
                  .fontSize(12)
                  .fontColor('#1f477d')
                  .maxLines(1)
                  .width('100%')
                  .margin({ top: 8 })
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#ffffff')
            .borderRadius(12)
            .margin({ bottom: 12 })
          })
        }
        .width('90%')
      }
      .layoutWeight(1)

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
      }

      if (this.uploadStage) {
        Text(this.uploadStage)
          .fontSize(13)
          .fontColor('#1f477d')
          .width('90%')
          .margin({ bottom: 8 })
      }

      // 确认按钮
      Button(this.isLoading ? '提交中...' : '确认选择并上传')
        .width('90%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .backgroundColor('#1f477d')
        .fontColor('#ffffff')
        .borderRadius(8)
        .enabled(!this.isLoading)
        .margin({ bottom: 16 })
        .onClick(() => {
          this.handleResubmit();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f2f5f9')
  }
}
