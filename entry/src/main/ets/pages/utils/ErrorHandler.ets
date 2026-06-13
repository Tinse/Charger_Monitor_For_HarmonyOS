// ErrorHandler.ets - 统一错误处理工具类

export class ErrorHandler {
  // 处理错误并记录日志
  static handle(error: Error, context: string): void {
    console.error(`[${context}] Error: ${error.message}`);
  }

  // 包装异步操作，自动处理错误
  static async wrap<T>(
    fn: () => Promise<T>,
    context: string,
    fallback?: T
  ): Promise<T | undefined> {
    try {
      return await fn();
    } catch (error) {
      if (error instanceof Error) {
        ErrorHandler.handle(error, context);
      } else {
        console.error(`[${context}] Unknown error:`, error);
      }
      return fallback;
    }
  }

  // 显示用户友好的错误提示
  static showToast(uiContext: UIContext, message: string, duration: number = 2000): void {
    try {
      uiContext.getPromptAction().openToast({
        message: message,
        duration: duration
      });
    } catch (error) {
      console.error('Failed to show toast:', error);
    }
  }

  // 创建 Toast 辅助函数（绑定 UIContext）
  static createToastHelper(uiContext: UIContext): (message: string, duration?: number) => void {
    return (message: string, duration: number = 2000) => {
      try {
        ErrorHandler.showToast(uiContext, message, duration);
      } catch (error) {
        console.error('Failed to show toast in helper:', error);
      }
    };
  }

  // 获取错误消息
  static getErrorMessage(error: Error): string {
    return error.message;
  }

  // 检查是否为网络错误
  static isNetworkError(error: Error): boolean {
    // 网络相关错误通常包含特定关键字
    const message = error.message.toLowerCase();
    return message.includes('network') || message.includes('timeout') || message.includes('connection');
  }
}