import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ErrorHandler } from '../utils/ErrorHandler';

export class NetworkState {
  private listener: connection.NetConnection | null = null;
  private sequence: number = 0;
  private registered: boolean = false;
  private resolved: boolean = false;
  private onChange?: (online: boolean) => void;

  start(onChange: (online: boolean) => void): void {
    this.stop();
    this.onChange = onChange;
    this.resolved = false;
    try {
      const listener = connection.createNetConnection();
      this.listener = listener;
      listener.register((error: BusinessError) => {
        if (error) {
          ErrorHandler.handle(error, 'NetworkState.register');
          return;
        }
        if (this.listener !== listener) {
          this.unregister(listener);
          return;
        }
        this.registered = true;
        const refreshCurrent = (): void => {
          if (this.listener === listener) this.refresh();
        };
        listener.on('netAvailable', refreshCurrent);
        listener.on('netLost', refreshCurrent);
        listener.on('netUnavailable', refreshCurrent);
        this.refresh();
      });
      this.refresh();
    } catch (error) {
      ErrorHandler.handle(error, 'NetworkState.start');
      this.refresh();
    }
  }

  async refresh(): Promise<void> {
    const sequence = ++this.sequence;
    try {
      const online = await connection.hasDefaultNet();
      if (sequence === this.sequence) {
        this.resolved = true;
        this.onChange?.(online);
      }
    } catch (error) {
      ErrorHandler.handle(error, 'NetworkState.refresh');
      // 无法判断系统网络时允许实际 HTTP 探测，后续事件仍可校正状态。
      if (sequence === this.sequence && !this.resolved) {
        this.resolved = true;
        this.onChange?.(true);
      }
    }
  }

  stop(): void {
    const listener = this.listener;
    this.listener = null;
    this.onChange = undefined;
    this.sequence++;
    if (listener && this.registered) this.unregister(listener);
    this.registered = false;
  }

  private unregister(listener: connection.NetConnection): void {
    try {
      listener.unregister((error: BusinessError) => {
        if (error) ErrorHandler.handle(error, 'NetworkState.unregister');
      });
    } catch (error) {
      ErrorHandler.handle(error, 'NetworkState.stop');
    }
  }
}
