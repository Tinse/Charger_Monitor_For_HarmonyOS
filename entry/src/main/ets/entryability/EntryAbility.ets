import { AbilityConstant, ConfigurationConstant, UIAbility, Want, Configuration } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppStateKeys } from '../pages/AppState';
import { ConfigManager } from '../pages/ConfigManager';

const DOMAIN = 0x0000;
const TAG = 'ChargerMonitor';

export default class EntryAbility extends UIAbility {
  async onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): Promise<void> {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      this.updateSystemDarkMode();
      // ApplicationContext 在页面创建前注入；所有配置读写共用同一个初始化 Promise。
      await ConfigManager.initialize(this.context.getApplicationContext());
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to initialize preferences: %{public}s', (error as BusinessError).message);
    }
  }

  private updateSystemDarkMode(colorMode?: ConfigurationConstant.ColorMode): void {
    const mode = colorMode ?? this.context.config.colorMode;
    AppStorage.setOrCreate<boolean>(AppStateKeys.SYSTEM_DARK_MODE,
      mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onConfigurationUpdate(config: Configuration): void {
    this.updateSystemDarkMode(config.colorMode);
    this.updateStatusBarStyle();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.setupWindow(windowStage).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'Failed to configure window: %{public}s', error.message);
    });
    windowStage.loadContent('pages/Index', (error: BusinessError) => {
      if (error && error.code !== 0) {
        hilog.error(DOMAIN, TAG, 'Failed to load content: %{public}s', error.message);
      }
    });
  }

  private async setupWindow(windowStage: window.WindowStage): Promise<void> {
    try {
      const mainWindow = await windowStage.getMainWindow();
      AppStorage.setOrCreate<window.Window>(AppStateKeys.WINDOW, mainWindow);
      await mainWindow.setWindowLayoutFullScreen(false);
      await mainWindow.setWindowSystemBarEnable(['status', 'navigation']);
      this.updateStatusBarStyle();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to configure window: %{public}s', (error as BusinessError).message);
    }
  }

  private updateStatusBarStyle(): void {
    const mainWindow = AppStorage.get<window.Window>(AppStateKeys.WINDOW);
    if (!mainWindow) {
      return;
    }
    const isDark = AppStorage.get<boolean>(AppStateKeys.SYSTEM_DARK_MODE) ?? false;
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      isStatusBarLightIcon: isDark,
      isNavigationBarLightIcon: isDark
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'Failed to style system bars: %{public}s', error.message);
    });
  }

  onWindowStageDestroy(): void {
    AppStorage.delete(AppStateKeys.WINDOW);
  }

  onForeground(): void {
    this.updateSystemDarkMode();
    this.updateStatusBarStyle();
  }
}
