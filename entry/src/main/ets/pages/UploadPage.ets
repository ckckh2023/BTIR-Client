import { router } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { TaskService, UploadArchiveOptions } from '../service/TaskService';
import { ApiError } from '../common/ApiError';
import { TokenManager } from '../common/HttpClient';
import { TaskCreatedResponse } from '../model/TaskModels';

@Entry
@Component
struct UploadPage {
  @State selectedFileUri: string = '';
  @State selectedFileName: string = '';
  @State taskName: string = '';
  @State caseId: string = '';
  @State caseName: string = '';
  @State studyDate: string = '';
  @State isLoading: boolean = false;
  @State uploadStage: string = '';
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
    this.isLoading = true;
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
          onStage: (stage: string) => { this.uploadStage = stage; }
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
          (stage: string) => { this.uploadStage = stage; }
        );
      }

      // 启动失败时仍进入已创建任务，详情页可确认状态并重试启动。
      this.uploadStage = '任务已创建，正在启动分析…';
      try {
        await this.taskService.runAsync(response.task_id);
      } catch (error) {
        // 请求可能已到达服务端，详情页会查询实际任务状态。
      }
      router.replaceUrl({
        url: 'pages/TaskDetailPage',
        params: { taskId: response.task_id }
      });
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

        Text(this.isFollowUp ? '新增复查' : '上传病例')
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
          Text('手机端可上传病例 ZIP，或分别选择四个 NIfTI 文件。DICOM 病例文件夹请先压缩成 ZIP。')
            .fontSize(13)
            .fontColor('#586b82')
            .width('100%')
            .margin({ bottom: 16 })

          if (this.isFollowUp) {
            Column() {
              Text(`新增复查：${this.caseName || this.caseId}`)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1f477d')
                .width('100%')
              Text(`本次检查将关联到病例 ID：${this.caseId}。可填写检查日期，并选择新的影像文件。`)
                .fontSize(13)
                .fontColor('#586b82')
                .width('100%')
                .margin({ top: 6, bottom: 10 })
              Button('改为新病例')
                .height(32)
                .fontSize(12)
                .backgroundColor('#e6edf5')
                .fontColor('#1f477d')
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

          // 上传模式切换
          Row() {
            Button('病例 ZIP')
              .layoutWeight(1)
              .height(38)
              .fontSize(14)
              .backgroundColor(this.uploadMode === 'zip' ? '#1f477d' : '#e6edf5')
              .fontColor(this.uploadMode === 'zip' ? '#ffffff' : '#586b82')
              .borderRadius(8)
              .onClick(() => {
                this.uploadMode = 'zip';
              })
              .margin({ right: 8 })

            Button('四模态 NIfTI')
              .layoutWeight(1)
              .height(38)
              .fontSize(14)
              .backgroundColor(this.uploadMode === 'nifti' ? '#1f477d' : '#e6edf5')
              .fontColor(this.uploadMode === 'nifti' ? '#ffffff' : '#586b82')
              .borderRadius(8)
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
              Text('ZIP 内应包含 FLAIR、T1CE、T1、T2 四个模态的 NIfTI 文件，或对应的 DICOM 序列。')
                .fontSize(13)
                .fontColor('#586b82')
                .width('100%')
                .margin({ bottom: 12 })

              if (this.selectedFileName) {
                Text(`已选择：${this.selectedFileName}`)
                  .fontSize(14)
                  .fontColor('#1f477d')
                  .fontWeight(FontWeight.Medium)
                  .width('100%')
                  .margin({ bottom: 12 })
              }

              Button(this.selectedFileName ? '重新选择 ZIP' : '选择 ZIP 文件')
                .width('100%')
                .height(44)
                .fontSize(16)
                .backgroundColor('#e6edf5')
                .fontColor('#1f477d')
                .borderRadius(8)
                .enabled(!this.isLoading)
                .onClick(() => {
                  this.selectZipFile();
                })
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#ffffff')
            .borderRadius(12)
            .margin({ bottom: 16 })
          }

          // NIfTI 上传模式
          if (this.uploadMode === 'nifti') {
            Column() {
              Text('请分别选择四个 .nii 或 .nii.gz 文件。')
                .fontSize(13)
                .fontColor('#586b82')
                .width('100%')
                .margin({ bottom: 12 })
              ForEach(['flair', 't1ce', 't1', 't2'], (modality: string) => {
                Row() {
                  Text(modality.toUpperCase())
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#1e2d3e')
                    .width(60)

                  Text(this.niftiFileNames[modality] ?? '未选择')
                    .fontSize(14)
                    .fontColor(this.niftiFileNames[modality] ? '#1f477d' : '#7d90a8')
                    .layoutWeight(1)

                  Button('选择')
                    .height(32)
                    .fontSize(12)
                    .backgroundColor('#e6edf5')
                    .fontColor('#1f477d')
                    .borderRadius(6)
                    .enabled(!this.isLoading)
                    .onClick(() => {
                      this.selectNiftiFile(modality);
                    })
                }
                .width('100%')
                .height(48)
                .padding({ left: 12, right: 12 })
                .margin({ bottom: 8 })
              })
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#ffffff')
            .borderRadius(12)
            .margin({ bottom: 16 })
          }

          if (!this.isFollowUp) {
            Button(this.showCaseDetails ? '收起病例信息' : '补充病例信息（可选）')
              .width('100%')
              .height(34)
              .fontSize(13)
              .backgroundColor('#e6edf5')
              .fontColor('#1f477d')
              .borderRadius(8)
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
                .fontColor('#1e2d3e')
                .margin({ bottom: 12 })

              TextInput({ text: this.taskName, placeholder: '任务名称' })
                .width('100%')
                .height(44)
                .fontSize(14)
                .backgroundColor('#f7f9fc')
                .borderRadius(8)
                .onChange((value: string) => {
                  this.taskName = value;
                })
                .margin({ bottom: 8 })

              if (this.isFollowUp) {
                Text(`病例 ID：${this.caseId}`)
                  .fontSize(14)
                  .fontColor('#586b82')
                  .width('100%')
                  .margin({ bottom: 8 })
              } else {
                TextInput({ text: this.caseId, placeholder: '病例 ID' })
                  .width('100%')
                  .height(44)
                  .fontSize(14)
                  .backgroundColor('#f7f9fc')
                  .borderRadius(8)
                  .onChange((value: string) => {
                    this.caseId = value;
                  })
                  .margin({ bottom: 8 })
              }

              TextInput({ text: this.caseName, placeholder: '病例名称' })
                .width('100%')
                .height(44)
                .fontSize(14)
                .backgroundColor('#f7f9fc')
                .borderRadius(8)
                .onChange((value: string) => {
                  this.caseName = value;
                })
                .margin({ bottom: 8 })

              TextInput({ text: this.studyDate, placeholder: '检查日期 (YYYY-MM-DD)' })
                .width('100%')
                .height(44)
                .fontSize(14)
                .backgroundColor('#f7f9fc')
                .borderRadius(8)
                .onChange((value: string) => {
                  this.studyDate = value;
                })
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#ffffff')
            .borderRadius(12)
            .margin({ bottom: 16 })
          }
        }
        .width('90%')
        .constraintSize({ minHeight: '100%' })
      }
      .layoutWeight(1)

      // 错误提示
      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor('#b42318')
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

      // 上传并分析按钮
      Button(this.isLoading ? '处理中…' : '开始数据分析')
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
          this.handleUpload();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f2f5f9')
  }
}
