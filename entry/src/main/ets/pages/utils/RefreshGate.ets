// 使用时间戳计算冷却，避免后台暂停或定时器延迟造成倒计时漂移。
export class RefreshGate {
  private expiresAt: number = 0;
  private pending: boolean = false;

  private duration: number;

  constructor(duration: number) { this.duration = duration; }

  remaining(now: number): number { return Math.max(0, this.expiresAt - now); }

  tryStart(now: number): boolean {
    if (this.pending || this.remaining(now) > 0) return false;
    this.pending = true;
    this.expiresAt = now + this.duration;
    return true;
  }

  finish(): void { this.pending = false; }
}
