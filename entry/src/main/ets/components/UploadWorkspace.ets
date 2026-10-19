import { PageHeader } from './PageHeader';
import { AppTheme } from '../common/AppTheme';
import { router } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { TaskService, UploadArchiveOptions } from '../service/TaskService';
import { ApiError } from '../common/ApiError';
import { TokenManager } from '../common/HttpClient';
import { TaskCreatedResponse } from '../model/TaskModels';

@Component
export struct UploadWorkspace {
  @Prop onHome: boolean = false;
  @State selectedFileUri: string = '';
  @State selectedFileName: string = '';
  @State taskName: string = '';
  @State caseId: string = '';
  @State caseName: string = '';
  @State studyDate: string = '';
  @State isLoading: boolean = false;
  @State uploadStage: string = '';
  @State uploadPercent: number = 0;
  @State errorMessage: string = '';
  @State uploadMode: string = 'zip';
  @State showCaseDetails: boolean = false;
  @State isFollowUp: boolean = false;
  @State niftiFiles: Record<string, string> = {};
  @State niftiFileNames: Record<string, string> = {};

  private taskService: TaskService = new TaskService();

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params && params['followUp'] === 'true' && params['caseId']) {
      this.caseId = params['caseId'];
      this.caseName = params['caseName'] || '';
      this.isFollowUp = true;
      this.showCaseDetails = true;
    }
  }

  private fileNameFromUri(uri: string): string {
    const path = uri.split('?')[0].split('#')[0];
    const encodedName = path.substring(path.lastIndexOf('/') + 1);
    try {
      return decodeURIComponent(encodedName);
    } catch (error) {
      return encodedName;
    }
  }

  async selectZipFile(): Promise<void> {
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.maxSelectNumber = 1;
      documentSelectOptions.fileSuffixFilters = ['.zip'];

      const documentViewPicker = new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext);
      const uris = await documentViewPicker.select(documentSelectOptions);

      if (uris && uris.length > 0) {
        this.selectedFileUri = uris[0];
        const fileName = this.fileNameFromUri(uris[0]);
        this.selectedFileName = fileName.toLowerCase().endsWith('.zip') ? fileName : '所选 ZIP 文件';
        this.errorMessage = '';
      }
    } catch (error) {
      this.errorMessage = `选择文件失败: ${String(error)}`;
    }
  }

  async selectNiftiFile(modality: string): Promise<void> {
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.maxSelectNumber = 1;
      documentSelectOptions.fileSuffixFilters = ['.nii', '.nii.gz'];

      const documentViewPicker = new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext);
      const uris = await documentViewPicker.select(documentSelectOptions);

      if (uris && uris.length > 0) {
        const files: Record<string, string> = {};
        for (const key of Object.keys(this.niftiFiles)) {
          files[key] = this.niftiFiles[key];
        }
        files[modality] = uris[0];
        this.niftiFiles = files;
        const fileNames: Record<string, string> = {};
        for (const key of Object.keys(this.niftiFileNames)) {
          fileNames[key] = this.niftiFileNames[key];
        }
        fileNames[modality] = this.fileNameFromUri(uris[0]);
        this.niftiFileNames = fileNames;
        this.errorMessage = '';
      }
    } catch (error) {
      this.errorMessage = `选择文件失败: ${String(error)}`;
    }
  }

  async handleUpload(): Promise<void> {
    if (this.isLoading) return;
    this.isLoading = true;
    this.uploadPercent = 0;
    this.errorMessage = '';
    this.uploadStage = '';

    try {
      let response: TaskCreatedResponse;
      const cacheDir = (getContext(this) as common.UIAbilityContext).cacheDir;

      if (this.uploadMode === 'zip') {
        if (!this.selectedFileUri) {
          this.errorMessage = '请先选择 ZIP 文件';
          this.isLoading = false;
          return;
        }
        const options: UploadArchiveOptions = {
          name: this.taskName.trim() || this.selectedFileName,
          caseId: this.caseId || undefined,
          caseName: this.caseName || undefined,
          studyDate: this.studyDate || undefined,
          onStage: (stage: string) => { this.uploadStage = stage; },
          onProgress: (percent: number) => { this.uploadPercent = Math.max(this.uploadPercent, percent); }
        };
        response = await this.taskService.uploadArchive(
          this.selectedFileUri, cacheDir, this.selectedFileName, options
        );
      } else {
        if (!this.niftiFiles['flair'] || !this.niftiFiles['t1ce'] ||
          !this.niftiFiles['t1'] || !this.niftiFiles['t2']) {
          this.errorMessage = '请选择全部四个模态文件';
          this.isLoading = false;
          return;
        }
        response = await this.taskService.uploadNiftiFiles(
          this.niftiFiles,
          this.niftiFileNames,
          cacheDir,
          this.taskName || undefined,
          this.caseId || undefined,
          this.caseName || undefined,
          this.studyDate || undefined,
          (stage: string) => { this.uploadStage = stage; },
          (percent: number) => { this.uploadPercent = Math.max(this.uploadPercent, percent); }
        );
      }

      // 启动失败时仍进入已创建任务，详情页可确认状态并重试启动。
      this.uploadStage = '任务已创建，正在启动分析…';
      try {
        await this.taskService.runAsync(response.task_id);
      } catch (error) {
        // 请求可能已到达服务端，详情页会查询实际任务状态。
      }
      const destination: router.RouterOptions = { url: 'pages/TaskDetailPage', params: { taskId: response.task_id } };
      if (this.onHome) {
        router.pushUrl(destination);
        this.selectedFileUri = ''; this.selectedFileName = ''; this.niftiFiles = {}; this.niftiFileNames = {};
        this.taskName = ''; this.caseId = ''; this.caseName = ''; this.studyDate = '';
        this.showCaseDetails = false; this.uploadMode = 'zip';
      } else { router.replaceUrl(destination); }
    } catch (error) {
      if (error instanceof ApiError) {
        if (error.isModalitySelection()) {
          // 422 模态选择，跳转到模态选择页面
          const modalitiesData = error.getModalitySelectionData();
          if (modalitiesData) {
            router.pushUrl({
              url: 'pages/ModalitySelectPage',
              params: {
                modalities: JSON.stringify(modalitiesData),
                code: error.code,
                archiveUri: this.selectedFileUri,
                archiveName: this.selectedFileName,
                taskName: this.taskName.trim() || this.selectedFileName,
                caseId: this.caseId,
                caseName: this.caseName,
                studyDate: this.studyDate,
              }
            });
            this.isLoading = false;
            return;
          }
        }
        if (error.isRateLimited()) {
          this.errorMessage = '请求过于频繁，请稍后再试';
        } else if (error.isServiceUnavailable()) {
          this.errorMessage = '服务暂时不可用';
        } else if (error.statusCode === 401) {
          this.errorMessage = '登录已过期，请重新登录';
          TokenManager.getInstance().clearAuth();
          router.replaceUrl({ url: 'pages/LoginPage' });
        } else {
          this.errorMessage = error.message;
        }
      } else {
        this.errorMessage = `上传失败: ${String(error)}`;
      }
    } finally {
      this.isLoading = false;
      this.uploadStage = '';
    }
  }

  @Builder
  SampleLink() {
    if (!this.isFollowUp) {
      Row({ space: 4 }) {
        Text('首次体验？').fontSize(13).fontColor(AppTheme.secondary)
        Button('下载测试样例').height(AppTheme.buttonHeight).fontSize(13).padding({ left: 0, right: 0 })
          .backgroundColor(AppTheme.surface).fontColor(AppTheme.primary).borderRadius(AppTheme.buttonRadius)
          .enabled(!this.isLoading).onClick(() => { router.pushUrl({ url: 'pages/SampleDownloadPage' }); })
      }.width('100%').justifyContent(FlexAlign.Center).margin({ top: 2 })
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      PageHeader({ title: this.onHome ? '智瞳医脑' : this.isFollowUp ? '新增复查' : '病例分析', onHome: this.onHome, canLeave: !this.isLoading })

      Row({ space: 20 }) {
        Text('病例分析').fontSize(14).fontWeight(FontWeight.Bold).fontColor(AppTheme.primary)
          .padding({ top: 12, bottom: 10 }).border({ width: { bottom: 2 }, color: AppTheme.primary })
        Button('任务管理').fontSize(14).height(AppTheme.buttonHeight).backgroundColor(AppTheme.background)
          .fontColor(AppTheme.secondary).enabled(!this.isLoading)
          .onClick(() => { router.pushUrl({ url: 'pages/TaskListPage' }); })
      }.width('100%').padding({ left: 20, right: 20 }).margin({ bottom: 16 })

      Scroll() {
        Column() {
          if (this.isFollowUp) {
            Column() {
              Text(`新增复查：${this.caseName || this.caseId}`)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.primary)
                .width('100%')
              Text(`本次上传将加入该病例的复查记录。`)
                .fontSize(13)
                .fontColor(AppTheme.secondary)
                .width('100%')
                .margin({ top: 6, bottom: 10 })
              Button('改为新病例')
                .height(AppTheme.buttonHeight)
                .fontSize(12)
                .backgroundColor(AppTheme.disabled)
                .fontColor(AppTheme.primary)
                .onClick(() => {
                  this.isFollowUp = false;
                  this.caseId = '';
                  this.caseName = '';
                })
            }
            .width('100%')
            .padding(14)
            .backgroundColor('#eaf2ff')
            .borderRadius(10)
            .margin({ bottom: 16 })
          }

          Text('选择病例影像').fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppTheme.text).width('100%').margin({ bottom: 8 })
          Text('上传 ZIP，或分别选择四个 NIfTI 文件').fontSize(14).fontColor(AppTheme.secondary).width('100%').margin({ bottom: 16 })

          // 上传模式切换
          Row() {
            Button('病例 ZIP')
              .layoutWeight(1)
              .height(AppTheme.buttonHeight)
              .fontSize(14)
              .backgroundColor(this.uploadMode === 'zip' ? AppTheme.primary : AppTheme.surface)
              .fontColor(this.uploadMode === 'zip' ? AppTheme.surface : AppTheme.secondary)
              .borderRadius(AppTheme.buttonRadius)
              .enabled(!this.isLoading)
              .onClick(() => {
                this.uploadMode = 'zip';
              })
              .margin({ right: 8 })

            Button('四模态 NIfTI')
              .layoutWeight(1)
              .height(AppTheme.buttonHeight)
              .fontSize(14)
              .backgroundColor(this.uploadMode === 'nifti' ? AppTheme.primary : AppTheme.surface)
              .fontColor(this.uploadMode === 'nifti' ? AppTheme.surface : AppTheme.secondary)
              .borderRadius(AppTheme.buttonRadius)
              .enabled(!this.isLoading)
              .onClick(() => {
                this.uploadMode = 'nifti';
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ bottom: 20 })

          // ZIP 上传模式
          if (this.uploadMode === 'zip') {
            Column() {
              Text('ZIP 需包含 FLAIR、T1CE、T1、T2 四模态 NIfTI 或 DICOM 文件。')
                .fontSize(13)
                .fontColor(AppTheme.secondary)
                .width('100%')
                .margin({ bottom: 12 })

              if (this.selectedFileName) {
                Text(`已选择：${this.selectedFileName}`)
                  .fontSize(14)
                  .fontColor(AppTheme.primary)
                  .fontWeight(FontWeight.Medium)
                  .width('100%')
                  .margin({ bottom: 12 })
              }

              Button(this.selectedFileName ? '重新选择 ZIP' : '选择 ZIP 压缩包')
                .width('100%')
                .height(76)
                .border({ width: 1, color: AppTheme.primary, style: BorderStyle.Dashed })
                .fontSize(16)
                .backgroundColor(AppTheme.disabled)
                .fontColor(AppTheme.primary)
                .borderRadius(AppTheme.buttonRadius)
                .enabled(!this.isLoading)
                .onClick(() => {
                  this.selectZipFile();
                })
              this.SampleLink()
            }
            .width('100%')
            .padding(AppTheme.pagePadding)
            .backgroundColor(AppTheme.surface)
            .borderRadius(AppTheme.cardRadius)
            .margin({ bottom: 16 })
          }

          // NIfTI 上传模式
          if (this.uploadMode === 'nifti') {
            Column() {
              Text('请分别选择四个 .nii 或 .nii.gz 文件。')
                .fontSize(13)
                .fontColor(AppTheme.secondary)
                .width('100%')
                .margin({ bottom: 12 })
              ForEach(['flair', 't1ce', 't1', 't2'], (modality: string) => {
                Row() {
                  Text(modality.toUpperCase())
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppTheme.text)
                    .width(60)

                  Text(this.niftiFileNames[modality] ?? '未选择')
                    .fontSize(14)
                    .fontColor(this.niftiFileNames[modality] ? AppTheme.primary : AppTheme.muted)
                    .layoutWeight(1)

                  Button('选择')
                    .height(AppTheme.buttonHeight)
                    .fontSize(12)
                    .backgroundColor(AppTheme.disabled)
                    .fontColor(AppTheme.primary)
                    .borderRadius(6)
                    .enabled(!this.isLoading)
                    .onClick(() => {
                      this.selectNiftiFile(modality);
                    })
                }
                .width('100%')
                .constraintSize({ minHeight: 48 })
                .padding({ left: 12, right: 12 })
                .margin({ bottom: 8 })
              })
              this.SampleLink()
            }
            .width('100%')
            .padding(AppTheme.pagePadding)
            .backgroundColor(AppTheme.surface)
            .borderRadius(AppTheme.cardRadius)
            .margin({ bottom: 16 })
          }

          if (!this.isFollowUp) {
            Button(this.showCaseDetails ? '收起病例信息' : '补充病例信息（可选）')
              .width('100%')
              .height(AppTheme.buttonHeight)
              .fontSize(13)
              .backgroundColor(AppTheme.background)
              .fontColor(AppTheme.secondary)
              .borderRadius(AppTheme.buttonRadius)
              .margin({ bottom: 12 })
              .onClick(() => {
                this.showCaseDetails = !this.showCaseDetails;
              })
          }

          // 病例信息
          if (this.showCaseDetails) {
            Column() {
              Text('病例信息')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.text)
                .margin({ bottom: 12 })

              TextInput({ text: this.taskName, placeholder: '任务名称' })
                .width('100%')
                .height(AppTheme.buttonHeight)
                .fontSize(14)
                .backgroundColor(AppTheme.subtle)
                .borderRadius(AppTheme.buttonRadius)
                .onChange((value: string) => {
                  this.taskName = value;
                })
                .margin({ bottom: 8 })

              if (this.isFollowUp) {
                Text(this.caseName || '当前病例').fontSize(14).fontColor(AppTheme.secondary).width('100%').margin({ bottom: 8 })
              } else {
                TextInput({ text: this.caseId, placeholder: '病例 ID' })
                  .width('100%')
                  .height(AppTheme.buttonHeight)
                  .fontSize(14)
                  .backgroundColor(AppTheme.subtle)
                  .borderRadius(AppTheme.buttonRadius)
                  .onChange((value: string) => {
                    this.caseId = value;
                  })
                  .margin({ bottom: 8 })
              }

              TextInput({ text: this.caseName, placeholder: '病例名称' })
                .width('100%')
                .height(AppTheme.buttonHeight)
                .fontSize(14)
                .backgroundColor(AppTheme.subtle)
                .borderRadius(AppTheme.buttonRadius)
                .onChange((value: string) => {
                  this.caseName = value;
                })
                .margin({ bottom: 8 })

              TextInput({ text: this.studyDate, placeholder: '检查日期 (YYYY-MM-DD)' })
                .width('100%')
                .height(AppTheme.buttonHeight)
                .fontSize(14)
                .backgroundColor(AppTheme.subtle)
                .borderRadius(AppTheme.buttonRadius)
                .onChange((value: string) => {
                  this.studyDate = value;
                })
            }
            .width('100%')
            .padding(AppTheme.pagePadding)
            .backgroundColor(AppTheme.surface)
            .borderRadius(AppTheme.cardRadius)
            .margin({ bottom: 16 })
          }
          // 错误提示
          if (this.errorMessage) {
            Text(this.errorMessage)
              .fontSize(14)
              .fontColor(AppTheme.danger)
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor(AppTheme.dangerBackground)
              .borderRadius(AppTheme.buttonRadius)
              .margin({ bottom: 8 })
          }

          if (this.uploadStage) {
            Text(this.uploadStage)
              .fontSize(13)
              .fontColor(AppTheme.primary)
              .width('100%')
              .margin({ bottom: 8 })
          }

          // 上传并分析按钮
          if (this.isLoading) {
            Progress({ value: this.uploadPercent / 10, total: 100, type: ProgressType.Linear })
              .width('100%').color(AppTheme.primary).margin({ top: 8, bottom: 4 })
            Text(`上传病例 · 整体进度 ${Math.floor(this.uploadPercent / 10)}%`)
              .width('100%').fontSize(12).fontColor(AppTheme.secondary).margin({ bottom: 8 })
          }

          Button(this.isLoading ? '处理中…' : '开始数据分析')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(AppTheme.primary)
            .fontColor(AppTheme.surface)
            .borderRadius(AppTheme.buttonRadius)
            .enabled(!this.isLoading && (this.uploadMode === 'zip' ? this.selectedFileUri.length > 0 :
              ['flair', 't1ce', 't1', 't2'].every((key: string): boolean => !!this.niftiFiles[key])))
            .margin({ bottom: 16 })
            .onClick(() => {
              this.handleUpload();
            })
        }
        .width('90%')
        .padding({ bottom: 24 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)

    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background)
  }
}
