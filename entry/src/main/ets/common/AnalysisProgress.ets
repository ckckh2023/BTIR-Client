interface PhaseBudget {
  start: number;
  end: number;
  duration: number;
}

// 与服务端 frontend/analysis-progress.js 的映射和时间曲线一致。
export class AnalysisProgress {
  phase: string = 'idle';
  raw: number = 0;
  private phaseStartedAt: number = 0;
  private sampleAt: number = 0;
  private lastFrameAt: number = -1;

  reset(): void {
    this.phase = 'idle';
    this.raw = 0;
    this.phaseStartedAt = 0;
    this.sampleAt = 0;
    this.lastFrameAt = -1;
  }

  pause(): void { this.lastFrameAt = -1; }

  private budget(): PhaseBudget {
    switch (this.phase) {
      case 'upload': return { start: 0, end: 10, duration: 15000 };
      case 'queued': return { start: 10, end: 10, duration: 0 };
      case 'classification': return { start: 10, end: 20, duration: 15000 };
      case 'segmentation': return { start: 20, end: 90, duration: 110000 };
      case 'summary': return { start: 90, end: 99, duration: 20000 };
      case 'complete': return { start: 100, end: 100, duration: 0 };
      default: return { start: 0, end: 0, duration: 0 };
    }
  }

  update(phase: string, raw: number, now: number): void {
    const value = Number.isFinite(raw) ? Math.min(100, Math.max(0, raw)) : 0;
    if (phase !== this.phase) {
      this.phase = phase;
      this.phaseStartedAt = now;
      this.sampleAt = now;
    } else if (value > this.raw) {
      this.sampleAt = now;
    }
    this.raw = Math.max(this.raw, value);
  }

  updateTask(status: string, raw?: number): void {
    const now = Date.now();
    if (status === 'succeeded') {
      this.update('complete', 100, now);
    } else if (status === 'queued') {
      this.update('queued', 36, now);
    } else if (status === 'running') {
      const value = Math.max(this.raw, Number.isFinite(raw) ? raw! : 36, 36);
      this.update(value >= 99 ? 'summary' : value >= 44 ? 'segmentation' : 'classification', value, now);
    }
  }

  get ceiling(): number { return this.budget().end; }

  get mappedPercent(): number {
    switch (this.phase) {
      case 'upload': return Math.min(1, Math.max(0, this.raw / 36)) * 10;
      case 'queued': return 10;
      case 'classification': return 10 + Math.min(1, Math.max(0, (this.raw - 36) / 8)) * 10;
      case 'segmentation': return 20 + Math.min(1, Math.max(0, (this.raw - 44) / 54)) * 70;
      case 'summary': return 90;
      case 'complete': return 100;
      default: return 0;
    }
  }

  target(now: number): number {
    const budget = this.budget();
    const elapsed = Math.max(0, now - this.phaseStartedAt);
    const mapped = this.mappedPercent;
    const eased = budget.duration ? 1 - Math.exp(-Math.LN10 * elapsed / budget.duration) : 0;
    if (this.phase === 'classification') return Math.max(mapped, Math.min(19.75, 10 + 10 * eased));
    if (this.phase === 'summary') return 90 + 9 * eased;
    if (this.phase === 'segmentation') {
      const lead = 2 * (1 - Math.exp(-Math.max(0, now - this.sampleAt) / (110000 / 70 * 2)));
      return Math.max(mapped, Math.min(89.75, mapped + lead));
    }
    return mapped;
  }

  advance(current: number, now: number): number {
    const elapsed = this.lastFrameAt < 0 ? 0 : Math.max(0, Math.min(100, now - this.lastFrameAt));
    this.lastFrameAt = now;
    const target = this.target(now);
    if (target <= current) return current;
    const next = this.phase === 'complete' ? Math.min(target, current + elapsed * 0.12) :
      current + (target - current) * (1 - Math.exp(-elapsed / 250));
    return target - next < 0.000001 ? target : next;
  }

  phaseState(index: number, status: string): string {
    if (status === 'succeeded') return 'done';
    if (status === 'queued' || status === 'created') return 'pending';
    if (status !== 'running') return 'paused';
    if (index === 0) return this.raw >= 44 ? 'done' : 'active';
    if (index === 1) return this.raw >= 99 ? 'done' : this.raw >= 44 ? 'active' : 'pending';
    return this.raw >= 99 ? 'active' : 'pending';
  }
}
