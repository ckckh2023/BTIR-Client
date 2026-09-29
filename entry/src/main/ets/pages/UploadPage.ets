import { router } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { TaskService } from '../service/TaskService';
import { ApiError } from '../common/ApiError';
import { TokenManager } from '../common/HttpClient';
import { TaskCreatedResponse, ArchiveModalitySelectionResponse } from '../model/TaskModels';

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
  @State errorMessage: string = '';
  @State uploadMode: string = 'zip';
  @State niftiFiles: Record<string, string> = {};
  @State niftiFileNames: Record<string, string> = {};

  private taskService: TaskService = new TaskService();

  async selectZipFile(): Promise<void> {
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.maxSelectNumber = 1;
      documentSelectOptions.fileSuffixFilters = ['.zip'];

      const documentViewPicker = new picker.DocumentViewPicker();
      const uris = await documentViewPicker.select(documentSelectOptions);

      if (uris && uris.length > 0) {
        this.selectedFileUri = uris[0];
        const uriParts = uris[0].split('/');
        this.selectedFileName = uriParts[uriParts.length - 1];
      }
    } catch (error) {
      this.errorMessage = `选择文件失败: ${String(error)}`;
    }
  }

  async selectNiftiFile(modality: string): Promise<void> {
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.maxSelectNumber = 1;
      documentSelectOptions.fileSuffixFilters = ['.nii', '.gz'];

      const documentViewPicker = new picker.DocumentViewPicker();
      const uris = await documentViewPicker.select(documentSelectOptions);

      if (uris && uris.length > 0) {
        this.niftiFiles[modality] = uris[0];
        const uriParts = uris[0].split('/');
        this.niftiFileNames[modality] = uriParts[uriParts.length - 1];
      }
    } catch (error) {
      this.errorMessage = `选择文件失败: ${String(error)}`;
    }
  }

  async handleUpload(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';

    try {
      let response: TaskCreatedResponse;

      if (this.uploadMode === 'zip') {
        if (!this.selectedFileUri) {
          this.errorMessage = '请先选择 ZIP 文件';
          this.isLoading = false;
          return;
        }
        response = await this.taskService.uploadArchive(
          this.selectedFileUri,
          this.taskName || undefined,
          this.caseId || undefined,
          this.caseName || undefined,
          this.studyDate || undefined
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
          this.taskName || undefined,
          this.caseId || undefined,
          this.caseName || undefined,
          this.studyDate || undefined
        );
      }

      // 上传成功，启动推理
      await this.taskService.runAsync(response.task_id);

      // 跳转到任务详情页
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
                taskName: this.taskName,
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
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('上传病例')
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

      Scroll() {
        Column() {
          // 上传模式切换
          Row() {
            Button('ZIP 压缩包')
              .height(40)
              .fontSize(14)
              .backgroundColor(this.uploadMode === 'zip' ? '#1A73E8' : '#E0E0E0')
              .fontColor(this.uploadMode === 'zip' ? '#FFFFFF' : '#666666')
              .onClick(() => {
                this.uploadMode = 'zip';
              })
              .margin({ right: 8 })

            Button('手动选择 NIfTI')
              .height(40)
              .fontSize(14)
              .backgroundColor(this.uploadMode === 'nifti' ? '#1A73E8' : '#E0E0E0')
              .fontColor(this.uploadMode === 'nifti' ? '#FFFFFF' : '#666666')
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
              if (this.selectedFileName) {
                Row() {
                  Text('已选择: ')
                    .fontSize(14)
                    .fontColor('#666666')
                  Text(this.selectedFileName)
                    .fontSize(14)
                    .fontColor('#1A73E8')
                    .fontWeight(FontWeight.Medium)
                }
                .width('100%')
                .margin({ bottom: 12 })
              }

              Button(this.selectedFileName ? '重新选择 ZIP' : '选择 ZIP 文件')
                .width('100%')
                .height(44)
                .fontSize(16)
                .backgroundColor('#F5F5F5')
                .fontColor('#333333')
                .borderRadius(8)
                .onClick(() => {
                  this.selectZipFile();
                })
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .margin({ bottom: 16 })
          }

          // NIfTI 上传模式
          if (this.uploadMode === 'nifti') {
            Column() {
              ForEach(['flair', 't1ce', 't1', 't2'], (modality: string) => {
                Row() {
                  Text(modality.toUpperCase())
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .width(60)

                  Text(this.niftiFileNames[modality] ?? '未选择')
                    .fontSize(14)
                    .fontColor(this.niftiFileNames[modality] ? '#1A73E8' : '#999999')
                    .layoutWeight(1)

                  Button('选择')
                    .height(32)
                    .fontSize(12)
                    .backgroundColor('#1A73E8')
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
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .margin({ bottom: 16 })
          }

          // 病例信息
          Column() {
            Text('病例信息（可选）')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .margin({ bottom: 12 })

            TextInput({ placeholder: '任务名称' })
              .width('100%')
              .height(44)
              .fontSize(14)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .onChange((value: string) => {
                this.taskName = value;
              })
              .margin({ bottom: 8 })

            TextInput({ placeholder: '病例 ID' })
              .width('100%')
              .height(44)
              .fontSize(14)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .onChange((value: string) => {
                this.caseId = value;
              })
              .margin({ bottom: 8 })

            TextInput({ placeholder: '病例名称' })
              .width('100%')
              .height(44)
              .fontSize(14)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .onChange((value: string) => {
                this.caseName = value;
              })
              .margin({ bottom: 8 })

            TextInput({ placeholder: '检查日期 (YYYY-MM-DD)' })
              .width('100%')
              .height(44)
              .fontSize(14)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .onChange((value: string) => {
                this.studyDate = value;
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .margin({ bottom: 16 })
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

      // 上传并分析按钮
      Button(this.isLoading ? '上传中...' : '上传并开始分析')
        .width('90%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .backgroundColor('#1A73E8')
        .borderRadius(8)
        .enabled(!this.isLoading)
        .margin({ bottom: 16 })
        .onClick(() => {
          this.handleUpload();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7FA')
  }
}
