import { TaskStatusResponse } from '../model/TaskModels';
import { ApiError } from './ApiError';

export interface MonitorFailure {
  error: Error;
  retryInMs: number;
  timedOut: boolean;
}

export function taskRunChanged(previous: TaskStatusResponse | null, next: TaskStatusResponse): boolean {
  if (!previous) return false;
  if (previous.task_id !== next.task_id) return true;
  if (previous.job && next.job && (previous.job.id !== next.job.id || previous.job.attempt !== next.job.attempt)) return true;
  return ['succeeded', 'partial', 'failed', 'canceled'].includes(previous.status) &&
    ['queued', 'running', 'cancel_requested'].includes(next.status);
}

export class TaskMonitor {
  private generation: number = 0;
  private active: boolean = false;
  private inFlight: boolean = false;
  private timer: number = -1;
  private taskId: string = '';
  private startedAt: number = 0;
  private failures: number = 0;

  private fetch: (id: string) => Promise<TaskStatusResponse>;
  private onResult: (task: TaskStatusResponse) => void;
  private onFailure: (failure: MonitorFailure) => void;

  constructor(fetch: (id: string) => Promise<TaskStatusResponse>,
    onResult: (task: TaskStatusResponse) => void,
    onFailure: (failure: MonitorFailure) => void) {
    this.fetch = fetch;
    this.onResult = onResult;
    this.onFailure = onFailure;
  }

  start(taskId: string): void {
    if (this.active && this.taskId === taskId) {
      if (this.timer >= 0) clearTimeout(this.timer);
      this.timer = -1;
      this.request();
      return;
    }
    this.stop();
    this.taskId = taskId;
    this.active = true;
    this.startedAt = Date.now();
    this.failures = 0;
    this.request();
  }

  stop(): void {
    this.generation++;
    this.active = false;
    this.inFlight = false;
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
  }

  private schedule(delay: number): void {
    if (!this.active) return;
    this.timer = setTimeout(() => { this.timer = -1; this.request(); }, delay);
  }

  private async request(): Promise<void> {
    if (!this.active || this.inFlight) return;
    if (Date.now() - this.startedAt >= 30 * 60 * 1000) {
      this.stop();
      this.onFailure({ error: new Error('自动刷新已超过 30 分钟，请手动刷新任务状态'), retryInMs: 0, timedOut: true });
      return;
    }
    const version = this.generation;
    this.inFlight = true;
    let delay = -1;
    try {
      const task = await this.fetch(this.taskId);
      if (!this.active || version !== this.generation) return;
      this.failures = 0;
      this.onResult(task);
      if (['running', 'queued', 'cancel_requested'].includes(task.status)) {
        const elapsed = Date.now() - this.startedAt;
        delay = elapsed < 15000 ? 500 : elapsed < 60000 ? 1500 : 3000;
      } else {
        this.active = false;
      }
    } catch (caught) {
      if (!this.active || version !== this.generation) return;
      const error = caught as Error;
      const permanent = error instanceof ApiError && [401, 403, 404].includes(error.statusCode);
      this.failures++;
      delay = permanent ? -1 : Math.min(15000, 1000 * Math.pow(2, Math.min(4, this.failures - 1)));
      if (permanent) this.active = false;
      this.onFailure({ error: error, retryInMs: Math.max(0, delay), timedOut: false });
    } finally {
      if (version === this.generation) {
        this.inFlight = false;
        if (delay >= 0) this.schedule(delay);
      }
    }
  }
}
