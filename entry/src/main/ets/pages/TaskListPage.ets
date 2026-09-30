import { router } from '@kit.ArkUI';
import { TaskService } from '../service/TaskService';
import { ApiError } from '../common/ApiError';
import { TokenManager } from '../common/HttpClient';
import { TaskListResponse, TaskSummaryResponse } from '../model/TaskModels';

@Entry
@Component
struct TaskListPage {
  @State tasks: TaskSummaryResponse[] = [];
  @State total: number = 0;
  @State currentPage: number = 1;
  @State pageSize: number = 20;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State statusFilter: string = '';
  @State searchQuery: string = '';

  private taskService: TaskService = new TaskService();

  aboutToAppear(): void {
    this.fetchTasks();
  }

  async fetchTasks(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';

    try {
      const offset = (this.currentPage - 1) * this.pageSize;
      const response = await this.taskService.getTaskList(
        this.pageSize,
        offset,
        this.statusFilter || undefined,
        this.searchQuery || undefined
      );
      this.tasks = response.items;
      this.total = response.total;
    } catch (error) {
      if (error instanceof ApiError && error.isTokenExpired()) {
        TokenManager.getInstance().clearAuth();
        router.replaceUrl({ url: 'pages/LoginPage' });
        return;
      }
      this.errorMessage = `获取列表失败: ${error instanceof ApiError ? error.message : String(error)}`;
    } finally {
      this.isLoading = false;
    }
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

  get totalPages(): number {
    return Math.ceil(this.total / this.pageSize);
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

        Text('病例列表')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1e2d3e')

        Blank()

        Button('上传')
          .height(32)
          .fontSize(12)
          .backgroundColor('#1f477d')
          .fontColor('#ffffff')
          .borderRadius(6)
          .onClick(() => {
            router.pushUrl({ url: 'pages/UploadPage' });
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#ffffff')

      // 搜索和筛选
      Row() {
        TextInput({ placeholder: '搜索...' })
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .backgroundColor('#f7f9fc')
          .borderRadius(8)
          .onChange((value: string) => {
            this.searchQuery = value;
          })
          .margin({ right: 8 })

        Button('搜索')
          .height(40)
          .fontSize(14)
          .backgroundColor('#1f477d')
          .fontColor('#ffffff')
          .borderRadius(8)
          .onClick(() => {
            this.currentPage = 1;
            this.fetchTasks();
          })
      }
      .width('90%')
      .margin({ top: 12, bottom: 8 })

      // 状态筛选
      Row() {
        ForEach(['', 'created', 'queued', 'running', 'succeeded', 'failed', 'canceled'], (status: string) => {
          Button(status === '' ? '全部' : this.getStatusText(status))
            .height(32)
            .fontSize(12)
            .backgroundColor(this.statusFilter === status ? '#1f477d' : '#e6edf5')
            .fontColor(this.statusFilter === status ? '#ffffff' : '#586b82')
            .borderRadius(6)
            .onClick(() => {
              this.statusFilter = status;
              this.currentPage = 1;
              this.fetchTasks();
            })
            .margin({ right: 4 })
        })
      }
      .width('90%')
      .margin({ bottom: 12 })

      // 任务列表
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
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.tasks.length === 0) {
        Column() {
          Text('暂无符合条件的任务')
            .fontSize(14)
            .fontColor('#7d90a8')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.tasks, (task: TaskSummaryResponse) => {
            ListItem() {
              Column() {
                Row() {
                  Text(task.name || task.task_id)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#1e2d3e')
                    .layoutWeight(1)

                  Text(this.getStatusText(task.status))
                    .fontSize(12)
                    .fontColor(this.getStatusColor(task.status))
                    .fontWeight(FontWeight.Medium)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .backgroundColor(this.getStatusBgColor(task.status))
                    .borderRadius(4)
                }
                .width('100%')
                .margin({ bottom: 4 })

                Row() {
                  Text(task.task_id)
                    .fontSize(12)
                    .fontColor('#7d90a8')
                    .layoutWeight(1)

                  if (task.case_name) {
                    Text(task.case_name)
                      .fontSize(12)
                      .fontColor('#586b82')
                      .margin({ right: 8 })
                  }

                  if (task.study_date) {
                    Text(task.study_date)
                      .fontSize(12)
                      .fontColor('#586b82')
                  }
                }
                .width('100%')

                if (task.error) {
                  Row() {
                    Text(task.error.message)
                      .fontSize(12)
                      .fontColor('#b42318')
                  }
                  .width('100%')
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor('#fee2e2')
                  .borderRadius(6)
                  .margin({ top: 4 })
                }
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#ffffff')
              .borderRadius(12)
              .margin({ bottom: 8 })
              .onClick(() => {
                router.pushUrl({
                  url: 'pages/TaskDetailPage',
                  params: { taskId: task.task_id }
                });
              })
            }
          }, (task: TaskSummaryResponse) => task.task_id)
        }
        .width('90%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0 })
      }
      if (this.total > this.pageSize) {
        Row() {
          Button('上一页')
            .height(36)
            .fontSize(12)
            .backgroundColor(this.currentPage > 1 ? '#1f477d' : '#e6edf5')
            .fontColor(this.currentPage > 1 ? '#ffffff' : '#7d90a8')
            .borderRadius(6)
            .enabled(this.currentPage > 1)
            .onClick(() => {
              this.currentPage--;
              this.fetchTasks();
            })
            .margin({ right: 8 })

          Text(`第 ${this.currentPage} / ${this.totalPages} 页，共 ${this.total} 项`)
            .fontSize(12)
            .fontColor('#586b82')

          Button('下一页')
            .height(36)
            .fontSize(12)
            .backgroundColor(this.currentPage < this.totalPages ? '#1f477d' : '#e6edf5')
            .fontColor(this.currentPage < this.totalPages ? '#ffffff' : '#7d90a8')
            .borderRadius(6)
            .enabled(this.currentPage < this.totalPages)
            .onClick(() => {
              this.currentPage++;
              this.fetchTasks();
            })
            .margin({ left: 8 })
        }
        .width('90%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 8, bottom: 8 })
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
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f2f5f9')
  }
}
