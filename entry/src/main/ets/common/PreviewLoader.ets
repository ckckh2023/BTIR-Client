import { TaskStatusResponse } from '../model/TaskModels';

export interface PreviewImage {
  key: string;
  path: string;
  label: string;
  kind: string;
  uri: string;
  error: boolean;
}

export function previewManifest(task: TaskStatusResponse): PreviewImage[] {
  const files = task.frontend_result?.result_files;
  const items: PreviewImage[] = [];
  if (!files) return items;
  if (files.preview) items.push({ key: 'overview', path: files.preview, label: '四模态分析概览', kind: 'overview', uri: '', error: false });
  const frames = files.preview_series?.frames || [];
  frames.forEach((frame, index: number) => {
    const position = frame.offset === 0 ? '最大病灶层' :
      frame.offset !== undefined ? (frame.offset < 0 ? '病灶前邻层' : '病灶后邻层') : '切片';
    const label = Number.isInteger(frame.slice_index) ? `${position} · 切片 ${frame.slice_index}` : position;
    if (frame.overlay) items.push({ key: `overlay_${index}`, path: frame.overlay, label: label, kind: 'overlay', uri: '', error: false });
    if (frame.raw) items.push({ key: `raw_${index}`, path: frame.raw, label: label, kind: 'raw', uri: '', error: false });
  });
  return items;
}

export class PreviewLoader {
  private version: number = 0;
  private identity: string = '';
  private loading: boolean = false;
  private cache: Record<string, string> = {};

  private download: (taskId: string, path: string) => Promise<string>;

  constructor(download: (taskId: string, path: string) => Promise<string>) { this.download = download; }

  cancel(): void { this.version++; this.loading = false; }
  clear(): void { this.cancel(); this.cache = {}; this.identity = ''; }

  async load(task: TaskStatusResponse, publish: (items: PreviewImage[]) => void): Promise<void> {
    const identity = `${task.task_id}/${task.job?.id || ''}/${task.updated_at}`;
    if (identity === this.identity && this.loading) return;
    this.cancel();
    if (identity !== this.identity) this.cache = {};
    this.identity = identity;
    this.loading = true;
    const version = this.version;
    const items = previewManifest(task);
    items.forEach((item: PreviewImage) => { item.uri = this.cache[item.path] || ''; });
    publish(items.slice());
    let next = 0;
    const worker = async (): Promise<void> => {
      while (version === this.version && next < items.length) {
        const item = items[next++];
        if (item.uri) continue;
        try {
          const uri = await this.download(task.task_id, item.path);
          if (version !== this.version) return;
          item.uri = uri;
          this.cache[item.path] = uri;
        } catch (error) {
          if (version !== this.version) return;
          item.error = true;
        }
        // 新对象触发 ArkUI 状态更新，完成一张就展示一张。
        publish(items.map((image: PreviewImage): PreviewImage => ({ key: image.key, path: image.path,
          label: image.label, kind: image.kind, uri: image.uri, error: image.error })));
      }
    };
    try {
      await Promise.all([worker(), worker(), worker()]);
    } finally {
      if (version === this.version) this.loading = false;
    }
  }
}
