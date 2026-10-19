import { activateLogo } from '../common/AppNavigation';
import { PageHeader } from '../components/PageHeader';
import { AppTheme } from '../common/AppTheme';
import { router } from '@kit.ArkUI';
import { TaskService } from '../service/TaskService';
import { ApiError } from '../common/ApiError';
import { TokenManager } from '../common/HttpClient';
import { TaskListResponse, TaskSummaryResponse } from '../model/TaskModels';
import { formatDate, taskStatusLabel } from '../common/ResultPresentation';

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
  private filterStatuses: string[] = ['', 'created', 'queued', 'running', 'partial', 'succeeded', 'failed', 'canceled'];

  private taskService: TaskService = new TaskService();
  private fetchVersion: number = 0;
  private pageVisible: boolean = false;
  private refreshTimer: number = -1;
  private refreshFailures: number = 0;
  private refreshBlocked: boolean = false;
  @State isRefreshing: boolean = false;

  private date(value?: string): string { return formatDate(value); }

  private stopRefresh(): void {
    if (this.refreshTimer >= 0) clearTimeout(this.refreshTimer);
    this.refreshTimer = -1;
  }

  onPageShow(): void { this.pageVisible = true; this.fetchTasks(); }
  onPageHide(): void {
    this.pageVisible = false;
    this.fetchVersion++;
    this.stopRefresh();
  }
  aboutToDisappear(): void { this.onPageHide(); }


  async fetchTasks(background: boolean = false): Promise<void> {
    if (!this.pageVisible || (background && this.isRefreshing)) return;
    this.stopRefresh();
    const version = ++this.fetchVersion;
    this.isLoading = this.tasks.length === 0 && !background;
    this.isRefreshing = true;
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
      this.refreshFailures = 0;
      this.refreshBlocked = false;
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
      this.refreshFailures++;
      this.refreshBlocked = error instanceof ApiError && [401, 403, 404].includes(error.statusCode);
      this.errorMessage = `获取列表失败: ${error instanceof ApiError ? error.message : String(error)}`;
    } finally {
      if (version === this.fetchVersion) {
        this.isLoading = false;
        this.isRefreshing = false;
        const active = this.tasks.some((task: TaskSummaryResponse) =>
          ['queued', 'running', 'cancel_requested'].includes(task.status));
        if (this.pageVisible && !this.refreshBlocked && this.listMode === 'active' && (active || this.refreshFailures > 0)) {
          const delay = this.refreshFailures ? Math.min(15000, 3000 * Math.pow(2, this.refreshFailures - 1)) : 3000;
          this.refreshTimer = setTimeout(() => { this.refreshTimer = -1; this.fetchTasks(true); }, delay);
        }
      }
    }
  }

  switchMode(mode: string): void {
    if (this.listMode === mode) return;
    this.listMode = mode;
    this.tasks = [];
    this.total = 0;
    this.currentPage = 1;
    this.statusFilter = '';
    this.pendingAction = '';
    this.pendingTaskId = '';
    this.successMessage = '';
    this.renameTaskId = '';
    this.renameDraft = '';
    this.manageTaskId = '';
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

  getStatusText(status: string): string { return taskStatusLabel(status); }

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
          .fontColor(AppTheme.text)
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

      Text(`检查日期：${this.date(task.study_date || task.created_at)}`)
        .fontSize(12)
        .fontColor(AppTheme.secondary)
        .width('100%')
        .margin({ top: 5 })

      if (this.listMode === 'archived') {
        Text(`归档于 ${this.date(task.archived_at)}`)
          .fontSize(11)
          .fontColor(AppTheme.muted)
          .width('100%')
          .margin({ top: 3 })
      }

      if (task.error) {
        Text(task.error.message)
          .fontSize(12)
          .fontColor(AppTheme.danger)
          .width('100%')
          .margin({ top: 7 })
      }

      Row() {
        Blank()
        if (this.listMode === 'active') {
          Button('查看详情')
            .height(AppTheme.buttonHeight)
            .fontSize(12)
            .backgroundColor('#eaf2ff')
            .fontColor(AppTheme.primary)
            .borderRadius(AppTheme.buttonRadius)
            .onClick(() => {
              router.pushUrl({
                url: 'pages/TaskDetailPage',
                params: { taskId: task.task_id }
              });
            })
        }
        Button(this.manageTaskId === task.task_id ? '收起管理' : '管理')
          .height(AppTheme.buttonHeight)
          .fontSize(12)
          .backgroundColor(AppTheme.disabled)
          .fontColor(AppTheme.primary)
          .borderRadius(AppTheme.buttonRadius)
          .margin({ left: this.listMode === 'active' ? 8 : 0 })
          .onClick(() => { this.toggleManage(task.task_id); })
      }
      .width('100%')
      .margin({ top: 10 })

      if (this.manageTaskId === task.task_id) {
        Column() {
          if (this.renameTaskId === task.task_id) {
            TextInput({ text: this.renameDraft, placeholder: '输入检查名称' })
              .width('100%')
              .height(AppTheme.buttonHeight)
              .maxLength(100)
              .backgroundColor(AppTheme.surface)
              .onChange((value: string) => { this.renameDraft = value; })
            Row() {
              Button(this.actionTaskId === task.task_id ? '保存中…' : '保存名称')
                .height(AppTheme.buttonHeight)
                .fontSize(12)
                .backgroundColor(AppTheme.primary)
                .fontColor(AppTheme.surface)
                .enabled(!this.actionTaskId)
                .onClick(() => { this.saveRename(task); })
              Button('取消')
                .height(AppTheme.buttonHeight)
                .fontSize(12)
                .backgroundColor(AppTheme.disabled)
                .fontColor(AppTheme.secondary)
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
              .fontColor(AppTheme.text)
              .width('100%')
              .margin({ bottom: 8 })
            Row() {
              Button('取消')
                .height(AppTheme.buttonHeight)
                .fontSize(12)
                .backgroundColor(AppTheme.disabled)
                .fontColor(AppTheme.secondary)
                .onClick(() => {
                  this.pendingAction = '';
                  this.pendingTaskId = '';
                })
              Button(this.actionTaskId === task.task_id ? '处理中…' : '确认')
                .height(AppTheme.buttonHeight)
                .fontSize(12)
                .backgroundColor(AppTheme.danger)
                .fontColor(AppTheme.surface)
                .enabled(!this.actionTaskId)
                .margin({ left: 8 })
                .onClick(() => { this.performAction(this.pendingAction, this.pendingTaskId); })
            }
          } else if (this.listMode === 'active') {
            Row() {
              Button('重命名')
                .enabled(!this.actionTaskId)
                .height(AppTheme.buttonHeight)
                .fontSize(12)
                .backgroundColor(AppTheme.surface)
                .fontColor(AppTheme.primary)
                .onClick(() => { this.beginRename(task); })
              if (this.canArchive(task.status)) {
                Button('归档检查')
                  .height(AppTheme.buttonHeight)
                  .fontSize(12)
                  .backgroundColor(AppTheme.surface)
                  .fontColor(AppTheme.danger)
                  .enabled(!this.actionTaskId)
                  .margin({ left: 8 })
                  .onClick(() => { this.requestAction('archive', task.task_id); })
              }
            }
          } else {
            Row() {
              Button(this.actionTaskId === task.task_id ? '恢复中…' : '恢复检查')
                .height(AppTheme.buttonHeight)
                .fontSize(12)
                .backgroundColor(AppTheme.surface)
                .fontColor(AppTheme.success)
                .enabled(!this.actionTaskId)
                .onClick(() => { this.performAction('restore', task.task_id); })
              Button('彻底删除')
                .height(AppTheme.buttonHeight)
                .fontSize(12)
                .backgroundColor(AppTheme.surface)
                .fontColor(AppTheme.danger)
                .enabled(!this.actionTaskId)
                .margin({ left: 8 })
                .onClick(() => { this.requestAction('purge', task.task_id); })
            }
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor(AppTheme.background)
        .borderRadius(AppTheme.buttonRadius)
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(AppTheme.surface)
    .borderRadius(AppTheme.cardRadius)
    .margin({ bottom: 8 })
  }

  build() {
    Column() {
      // 顶部标题栏
      PageHeader({ title: '任务管理', canLeave: !this.actionTaskId })
      Row({ space: 20 }) {
        Button('病例分析').fontSize(14).height(AppTheme.buttonHeight).backgroundColor(AppTheme.background)
          .fontColor(AppTheme.secondary).onClick(() => { activateLogo(); })
        Text('任务管理').fontSize(14).fontWeight(FontWeight.Bold).fontColor(AppTheme.primary)
          .padding({ top: 12, bottom: 10 }).border({ width: { bottom: 2 }, color: AppTheme.primary })
      }.width('100%').padding({ left: 20, right: 20 })

      Row() {
        Button('病例检查')
          .layoutWeight(1)
          .height(AppTheme.buttonHeight)
          .fontSize(14)
          .backgroundColor(this.listMode === 'active' ? AppTheme.selected : AppTheme.surface)
          .fontColor(this.listMode === 'active' ? AppTheme.primary : AppTheme.secondary)
          .borderRadius(AppTheme.buttonRadius)
          .onClick(() => { this.switchMode('active'); })
          .margin({ right: 8 })

        Button('已归档')
          .layoutWeight(1)
          .height(AppTheme.buttonHeight)
          .fontSize(14)
          .backgroundColor(this.listMode === 'archived' ? AppTheme.selected : AppTheme.surface)
          .fontColor(this.listMode === 'archived' ? AppTheme.primary : AppTheme.secondary)
          .borderRadius(AppTheme.buttonRadius)
          .onClick(() => { this.switchMode('archived'); })
      }
      .width('90%')
      .margin({ top: 12 })

      // 搜索和筛选
      Row() {
        TextInput({ placeholder: '搜索...' })
          .layoutWeight(1)
          .height(AppTheme.buttonHeight)
          .fontSize(14)
          .backgroundColor(AppTheme.subtle)
          .borderRadius(AppTheme.buttonRadius)
          .onChange((value: string) => {
            this.searchQuery = value;
          })
          .margin({ right: 8 })

        Button('搜索')
          .height(AppTheme.buttonHeight)
          .fontSize(14)
          .backgroundColor(AppTheme.primary)
          .fontColor(AppTheme.surface)
          .borderRadius(AppTheme.buttonRadius)
          .onClick(() => {
            this.currentPage = 1;
            this.fetchTasks();
          })
        Select(this.filterStatuses.map((status: string): SelectOption => ({
          value: status ? this.getStatusText(status) : '全部状态'
        })))
          .selected(Math.max(0, this.filterStatuses.indexOf(this.statusFilter)))
          .value(this.statusFilter ? this.getStatusText(this.statusFilter) : '全部状态')
          .width(112).height(AppTheme.buttonHeight).font({ size: 13 })
          .fontColor(AppTheme.primary).backgroundColor(AppTheme.subtle).borderRadius(AppTheme.buttonRadius)
          .margin({ left: 8 })
          .onSelect((index: number) => {
            if (index < 0 || index >= this.filterStatuses.length) return;
            this.statusFilter = this.filterStatuses[index];
            this.currentPage = 1;
            this.fetchTasks();
          })
      }
      .width('90%')
      .margin({ top: 12, bottom: 8 })

      // 同一病例的检查归在一组；分页仍由服务端按检查记录计算。
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
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.tasks.length === 0) {
        Column() {
          Text(this.listMode === 'archived' ? '暂无归档检查' : '暂无符合条件的检查')
            .fontSize(14)
            .fontColor(AppTheme.muted)
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
                      .fontColor(AppTheme.text)
                      .width('100%')
                    Text(`本页 ${group.tasks.length} 次检查`)
                      .fontSize(11)
                      .fontColor(AppTheme.secondary)
                      .width('100%')
                      .margin({ top: 4 })
                  }
                  .layoutWeight(1)

                  if (this.listMode === 'active') {
                    Button('新增复查')
                      .enabled(!this.actionTaskId)
                      .height(AppTheme.buttonHeight)
                      .fontSize(12)
                      .backgroundColor(AppTheme.primary)
                      .fontColor(AppTheme.surface)
                      .borderRadius(AppTheme.buttonRadius)
                      .margin({ left: 8 })
                      .onClick(() => { this.startFollowUp(group.tasks[0]); })
                  }
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 14, bottom: 12 })
                .backgroundColor('#eaf2ff')
                .borderRadius(AppTheme.cardRadius)
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
          .fontColor(AppTheme.success)
          .width('90%')
          .padding(10)
          .backgroundColor(AppTheme.successBackground)
          .borderRadius(AppTheme.buttonRadius)
          .margin({ bottom: 8 })
      }
      if (this.total > this.pageSize) {
        Row() {
          Button('上一页')
            .height(AppTheme.buttonHeight)
            .fontSize(12)
            .backgroundColor(this.currentPage > 1 ? AppTheme.selected : AppTheme.surface)
            .fontColor(this.currentPage > 1 ? AppTheme.surface : AppTheme.muted)
            .borderRadius(6)
            .enabled(this.currentPage > 1)
            .onClick(() => {
              this.currentPage--;
              this.fetchTasks();
            })
            .margin({ right: 8 })

          Text(`第 ${this.currentPage} / ${this.totalPages} 页，共 ${this.total} 项`)
            .fontSize(12)
            .fontColor(AppTheme.secondary)

          Button('下一页')
            .height(AppTheme.buttonHeight)
            .fontSize(12)
            .backgroundColor(this.currentPage < this.totalPages ? AppTheme.selected : AppTheme.surface)
            .fontColor(this.currentPage < this.totalPages ? AppTheme.surface : AppTheme.muted)
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
          .fontColor(AppTheme.danger)
          .width('90%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(AppTheme.dangerBackground)
          .borderRadius(AppTheme.buttonRadius)
          .margin({ bottom: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background)
  }
}
