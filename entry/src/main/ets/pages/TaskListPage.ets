import { router } from '@kit.ArkUI';
import { TaskService } from '../service/TaskService';
import { ApiError } from '../common/ApiError';
import { TokenManager } from '../common/HttpClient';
import { TaskListResponse, TaskSummaryResponse } from '../model/TaskModels';

interface CaseGroup {
  caseId: string;
  name: string;
  tasks: TaskSummaryResponse[];
}

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
  @State listMode: string = 'active';
  @State pendingAction: string = '';
  @State pendingTaskId: string = '';
  @State actionTaskId: string = '';
  @State successMessage: string = '';
  @State renameTaskId: string = '';
  @State renameDraft: string = '';
  @State manageTaskId: string = '';
  @State showFilters: boolean = false;

  private taskService: TaskService = new TaskService();
  private fetchVersion: number = 0;

  aboutToAppear(): void {
    this.fetchTasks();
  }

  async fetchTasks(): Promise<void> {
    const version = ++this.fetchVersion;
    this.isLoading = true;
    this.errorMessage = '';

    try {
      const mode = this.listMode;
      const offset = (this.currentPage - 1) * this.pageSize;
      const response = mode === 'archived'
        ? await this.taskService.getArchivedTasks(this.pageSize, offset,
          this.statusFilter || undefined, this.searchQuery || undefined)
        : await this.taskService.getTaskList(this.pageSize, offset,
          this.statusFilter || undefined, this.searchQuery || undefined);
      if (version !== this.fetchVersion) return;
      this.tasks = response.items;
      this.total = response.total;
      if (this.tasks.length === 0 && this.total > 0 && this.currentPage > 1) {
        this.currentPage = Math.ceil(this.total / this.pageSize);
        await this.fetchTasks();
      }
    } catch (error) {
      if (version !== this.fetchVersion) return;
      if (error instanceof ApiError && error.isTokenExpired()) {
        TokenManager.getInstance().clearAuth();
        router.replaceUrl({ url: 'pages/LoginPage' });
        return;
      }
      this.errorMessage = `获取列表失败: ${error instanceof ApiError ? error.message : String(error)}`;
    } finally {
      if (version === this.fetchVersion) this.isLoading = false;
    }
  }

  switchMode(mode: string): void {
    if (this.listMode === mode) return;
    this.listMode = mode;
    this.currentPage = 1;
    this.statusFilter = '';
    this.pendingAction = '';
    this.pendingTaskId = '';
    this.successMessage = '';
    this.renameTaskId = '';
    this.renameDraft = '';
    this.manageTaskId = '';
    this.showFilters = false;
    this.fetchTasks();
  }

  caseGroups(): CaseGroup[] {
    const groups: CaseGroup[] = [];
    for (const task of this.tasks) {
      const caseId = task.case_id || task.task_id;
      let group: CaseGroup | undefined = groups.find((item: CaseGroup) => item.caseId === caseId);
      if (!group) {
        group = { caseId: caseId, name: task.case_name || task.name || '未命名病例', tasks: [] };
        groups.push(group);
      }
      group.tasks.push(task);
    }
    return groups;
  }

  startFollowUp(task: TaskSummaryResponse): void {
    router.pushUrl({
      url: 'pages/UploadPage',
      params: {
        followUp: 'true',
        caseId: task.case_id || task.task_id,
        caseName: task.case_name || task.name || '当前病例'
      }
    });
  }

  beginRename(task: TaskSummaryResponse): void {
    this.renameTaskId = task.task_id;
    this.renameDraft = task.name || '';
    this.manageTaskId = task.task_id;
    this.errorMessage = '';
    this.successMessage = '';
  }

  toggleManage(taskId: string): void {
    const closing = this.manageTaskId === taskId;
    this.manageTaskId = closing ? '' : taskId;
    this.renameTaskId = '';
    this.renameDraft = '';
    this.pendingAction = '';
    this.pendingTaskId = '';
  }

  async saveRename(task: TaskSummaryResponse): Promise<void> {
    const name = this.renameDraft.trim();
    if (!name || name.length > 100) {
      this.errorMessage = '任务名称应为 1–100 个字符';
      return;
    }
    if (name === task.name) {
      this.renameTaskId = '';
      return;
    }
    if (this.actionTaskId) return;
    this.actionTaskId = task.task_id;
    try {
      await this.taskService.renameTask(task.task_id, name);
      this.renameTaskId = '';
      this.renameDraft = '';
      this.manageTaskId = '';
      this.successMessage = '重命名成功，同一病例的病例名已同步更新';
      await this.fetchTasks();
    } catch (error) {
      if (error instanceof ApiError && error.isTokenExpired()) {
        TokenManager.getInstance().clearAuth();
        router.replaceUrl({ url: 'pages/LoginPage' });
        return;
      }
      this.errorMessage = `重命名失败：${error instanceof ApiError ? error.message : String(error)}`;
    } finally {
      this.actionTaskId = '';
    }
  }

  canArchive(status: string): boolean {
    return ['created', 'partial', 'succeeded', 'failed', 'canceled'].includes(status);
  }

  requestAction(action: string, taskId: string): void {
    this.pendingAction = action;
    this.pendingTaskId = taskId;
    this.manageTaskId = taskId;
    this.errorMessage = '';
    this.successMessage = '';
  }

  async performAction(action: string, taskId: string): Promise<void> {
    if (this.actionTaskId) return;
    this.actionTaskId = taskId;
    this.errorMessage = '';
    this.successMessage = '';
    try {
      if (action === 'archive') {
        await this.taskService.deleteTask(taskId);
        this.successMessage = '任务已移入归档列表，可在宽限期内恢复';
      } else if (action === 'restore') {
        await this.taskService.restoreTask(taskId);
        this.successMessage = '任务已恢复到病例列表';
      } else if (action === 'purge') {
        await this.taskService.purgeTask(taskId);
        this.successMessage = '任务已彻底删除';
      }
      this.pendingAction = '';
      this.pendingTaskId = '';
      this.manageTaskId = '';
      if (this.tasks.length === 1 && this.currentPage > 1) this.currentPage--;
      await this.fetchTasks();
    } catch (error) {
      if (error instanceof ApiError && error.isTokenExpired()) {
        TokenManager.getInstance().clearAuth();
        router.replaceUrl({ url: 'pages/LoginPage' });
        return;
      }
      this.errorMessage = `${action === 'archive' ? '归档' : action === 'restore' ? '恢复' : '彻底删除'}失败: ${error instanceof ApiError ? error.message : String(error)}`;
    } finally {
      this.actionTaskId = '';
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

  @Builder
  TaskCard(task: TaskSummaryResponse) {
    Column() {
      Row() {
        Text(task.name || '未命名检查')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1e2d3e')
          .layoutWeight(1)
        Text(this.getStatusText(task.status))
          .fontSize(11)
          .fontColor(this.getStatusColor(task.status))
          .padding({ left: 7, right: 7, top: 4, bottom: 4 })
          .backgroundColor(this.getStatusBgColor(task.status))
          .borderRadius(6)
          .margin({ left: 8 })
      }
      .width('100%')

      Text(`检查日期：${task.study_date || task.created_at}`)
        .fontSize(12)
        .fontColor('#586b82')
        .width('100%')
        .margin({ top: 5 })

      if (this.listMode === 'archived') {
        Text(`归档于 ${task.archived_at || '未知时间'}`)
          .fontSize(11)
          .fontColor('#7d90a8')
          .width('100%')
          .margin({ top: 3 })
      }

      if (task.error) {
        Text(task.error.message)
          .fontSize(12)
          .fontColor('#b42318')
          .width('100%')
          .margin({ top: 7 })
      }

      Row() {
        Blank()
        if (this.listMode === 'active') {
          Button('查看详情')
            .height(34)
            .fontSize(12)
            .backgroundColor('#eaf2ff')
            .fontColor('#1f477d')
            .borderRadius(8)
            .onClick(() => {
              router.pushUrl({
                url: 'pages/TaskDetailPage',
                params: { taskId: task.task_id }
              });
            })
        }
        Button(this.manageTaskId === task.task_id ? '收起管理' : '管理')
          .height(34)
          .fontSize(12)
          .backgroundColor('#e6edf5')
          .fontColor('#1f477d')
          .borderRadius(8)
          .margin({ left: this.listMode === 'active' ? 8 : 0 })
          .onClick(() => { this.toggleManage(task.task_id); })
      }
      .width('100%')
      .margin({ top: 10 })

      if (this.manageTaskId === task.task_id) {
        Column() {
          Text(`任务 ID：${task.task_id}`)
            .fontSize(11)
            .fontColor('#7d90a8')
            .width('100%')
            .margin({ bottom: 8 })

          if (this.renameTaskId === task.task_id) {
            TextInput({ text: this.renameDraft, placeholder: '输入检查名称' })
              .width('100%')
              .height(40)
              .maxLength(100)
              .backgroundColor('#ffffff')
              .onChange((value: string) => { this.renameDraft = value; })
            Row() {
              Button('保存名称')
                .height(32)
                .fontSize(12)
                .backgroundColor('#1f477d')
                .fontColor('#ffffff')
                .enabled(!this.actionTaskId)
                .onClick(() => { this.saveRename(task); })
              Button('取消')
                .height(32)
                .fontSize(12)
                .backgroundColor('#e6edf5')
                .fontColor('#586b82')
                .margin({ left: 8 })
                .onClick(() => {
                  this.renameTaskId = '';
                  this.renameDraft = '';
                })
            }
            .margin({ top: 8 })
          } else if (this.pendingAction && this.pendingTaskId === task.task_id) {
            Text(this.pendingAction === 'purge'
              ? '彻底删除后无法恢复，确认删除这次检查？'
              : '归档后可从“已归档”恢复，确认归档这次检查？')
              .fontSize(13)
              .fontColor('#1e2d3e')
              .width('100%')
              .margin({ bottom: 8 })
            Row() {
              Button('取消')
                .height(32)
                .fontSize(12)
                .backgroundColor('#e6edf5')
                .fontColor('#586b82')
                .onClick(() => {
                  this.pendingAction = '';
                  this.pendingTaskId = '';
                })
              Button('确认')
                .height(32)
                .fontSize(12)
                .backgroundColor('#b42318')
                .fontColor('#ffffff')
                .enabled(!this.actionTaskId)
                .margin({ left: 8 })
                .onClick(() => { this.performAction(this.pendingAction, this.pendingTaskId); })
            }
          } else if (this.listMode === 'active') {
            Row() {
              Button('重命名')
                .height(32)
                .fontSize(12)
                .backgroundColor('#ffffff')
                .fontColor('#1f477d')
                .onClick(() => { this.beginRename(task); })
              if (this.canArchive(task.status)) {
                Button('归档检查')
                  .height(32)
                  .fontSize(12)
                  .backgroundColor('#ffffff')
                  .fontColor('#b42318')
                  .enabled(!this.actionTaskId)
                  .margin({ left: 8 })
                  .onClick(() => { this.requestAction('archive', task.task_id); })
              }
            }
          } else {
            Row() {
              Button('恢复检查')
                .height(32)
                .fontSize(12)
                .backgroundColor('#ffffff')
                .fontColor('#18794e')
                .enabled(!this.actionTaskId)
                .onClick(() => { this.performAction('restore', task.task_id); })
              Button('彻底删除')
                .height(32)
                .fontSize(12)
                .backgroundColor('#ffffff')
                .fontColor('#b42318')
                .enabled(!this.actionTaskId)
                .margin({ left: 8 })
                .onClick(() => { this.requestAction('purge', task.task_id); })
            }
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#f2f5f9')
        .borderRadius(8)
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#ffffff')
    .borderRadius(12)
    .margin({ bottom: 8 })
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

      Row() {
        Button('病例检查')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(this.listMode === 'active' ? '#1f477d' : '#e6edf5')
          .fontColor(this.listMode === 'active' ? '#ffffff' : '#586b82')
          .borderRadius(8)
          .onClick(() => { this.switchMode('active'); })
          .margin({ right: 8 })

        Button('已归档')
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .backgroundColor(this.listMode === 'archived' ? '#1f477d' : '#e6edf5')
          .fontColor(this.listMode === 'archived' ? '#ffffff' : '#586b82')
          .borderRadius(8)
          .onClick(() => { this.switchMode('archived'); })
      }
      .width('90%')
      .margin({ top: 12 })

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

      Button(this.showFilters ? '收起状态筛选' :
        this.statusFilter ? `状态：${this.getStatusText(this.statusFilter)}  ·  更改` : '筛选状态')
        .height(32)
        .fontSize(12)
        .backgroundColor('#e6edf5')
        .fontColor('#1f477d')
        .borderRadius(8)
        .onClick(() => { this.showFilters = !this.showFilters; })
        .margin({ bottom: 10 })

      if (this.showFilters) {
        Scroll() {
          Row() {
            ForEach(['', 'created', 'queued', 'running', 'partial', 'succeeded', 'failed', 'canceled'], (status: string) => {
              Button(status === '' ? '全部' : this.getStatusText(status))
                .height(32)
                .fontSize(12)
                .backgroundColor(this.statusFilter === status ? '#1f477d' : '#e6edf5')
                .fontColor(this.statusFilter === status ? '#ffffff' : '#586b82')
                .borderRadius(6)
                .onClick(() => {
                  this.statusFilter = status;
                  this.currentPage = 1;
                  this.showFilters = false;
                  this.fetchTasks();
                })
                .margin({ right: 6 })
            })
          }
        }
        .width('90%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .margin({ bottom: 12 })
      }

      // 同一病例的检查归在一组；分页仍由服务端按检查记录计算。
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
          Text(this.listMode === 'archived' ? '暂无归档检查' : '暂无符合条件的检查')
            .fontSize(14)
            .fontColor('#7d90a8')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.caseGroups(), (group: CaseGroup) => {
            ListItem() {
              Column() {
                Row() {
                  Column() {
                    Text(group.name)
                      .fontSize(17)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#1e2d3e')
                      .width('100%')
                    Text(`病例 ID：${group.caseId} · 本页 ${group.tasks.length} 次检查`)
                      .fontSize(11)
                      .fontColor('#586b82')
                      .width('100%')
                      .margin({ top: 4 })
                  }
                  .layoutWeight(1)

                  if (this.listMode === 'active') {
                    Button('新增复查')
                      .height(34)
                      .fontSize(12)
                      .backgroundColor('#1f477d')
                      .fontColor('#ffffff')
                      .borderRadius(8)
                      .margin({ left: 8 })
                      .onClick(() => { this.startFollowUp(group.tasks[0]); })
                  }
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 14, bottom: 12 })
                .backgroundColor('#eaf2ff')
                .borderRadius(12)
                .margin({ bottom: 8 })

                ForEach(group.tasks, (task: TaskSummaryResponse) => {
                  this.TaskCard(task)
                }, (task: TaskSummaryResponse) => task.task_id)
              }
              .width('100%')
              .margin({ bottom: 12 })
            }
          }, (group: CaseGroup) => group.caseId)
        }
        .width('90%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0 })
      }

      if (this.successMessage) {
        Text(this.successMessage)
          .fontSize(13)
          .fontColor('#18794e')
          .width('90%')
          .padding(10)
          .backgroundColor('#dcfce7')
          .borderRadius(8)
          .margin({ bottom: 8 })
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
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor('#b42318')
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
