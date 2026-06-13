import { AbilityConstant, ConfigurationConstant, UIAbility, Want, abilityAccessCtrl, bundleManager, Permissions, PermissionRequestResult, common, Configuration } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppStateKeys } from '../pages/AppState';
import { LOCATION_PERMISSIONS } from '../pages/services/LocationService';

const DOMAIN = 0x0000;

// 系统主题状态的 AppStorage key (使用 AppStateKeys)
export const APP_STORAGE_KEY_SYSTEM_DARK_MODE = AppStateKeys.SYSTEM_DARK_MODE;

// 窗口实例存储 key
const APP_STORAGE_KEY_WINDOW = 'app.window';

export default class EntryAbility extends UIAbility {
  private windowStage: window.WindowStage | null = null;

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', error.message);
    }

    // 初始化系统主题状态到 AppStorage
    this.updateSystemDarkMode();

    // 检查定位权限状态（不自动申请，遵循最小权限原则）
    await this.checkLocationPermissions();

    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  // 更新系统深色模式状态到 AppStorage
  private updateSystemDarkMode(colorMode?: ConfigurationConstant.ColorMode): void {
    try {
      // 使用传入的 colorMode 或从 context 获取
      const mode = colorMode ?? this.context.config.colorMode;
      // colorMode: COLOR_MODE_DARK = 0, COLOR_MODE_LIGHT = 1
      const isDark = mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      AppStorage.setOrCreate<boolean>(APP_STORAGE_KEY_SYSTEM_DARK_MODE, isDark);
      hilog.info(DOMAIN, 'testTag', 'System dark mode updated: %{public}s, colorMode: %{public}d', isDark.toString(), mode);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'Failed to update system dark mode: %{public}s', error.message);
      // 默认深色
      AppStorage.setOrCreate<boolean>(APP_STORAGE_KEY_SYSTEM_DARK_MODE, true);
    }
  }

  // 监听系统配置变化（包括主题变化）
  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, 'testTag', 'Configuration updated, colorMode: %{public}d', newConfig.colorMode);
    // 使用 newConfig.colorMode 更新系统深色模式状态
    this.updateSystemDarkMode(newConfig.colorMode);
    // 更新状态栏颜色
    this.updateStatusBarStyle(newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 主窗口被创建，设置主页面
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 保存 windowStage 引用
    this.windowStage = windowStage;

    // 设置沉浸式布局
    this.setupImmersiveLayout(windowStage);

    windowStage.loadContent('pages/Index', (err) => {
      if (err) {
        const error = err as BusinessError;
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', error.message);
        return;
      }
    });
  }

  // 设置沉浸式布局
  private setupImmersiveLayout(windowStage: window.WindowStage): void {
    try {
      // 获取主窗口
      windowStage.getMainWindow((err: BusinessError, win: window.Window) => {
        if (err.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to get main window. Cause: %{public}s', err.message);
          return;
        }

        // 保存窗口实例到 AppStorage，供页面使用
        AppStorage.setOrCreate<window.Window>(APP_STORAGE_KEY_WINDOW, win);

        // 不使用全屏布局，让布局自动避让状态栏
        win.setWindowLayoutFullScreen(false).then(() => {
          hilog.info(DOMAIN, 'testTag', 'Window layout set to non-full screen');

          // 设置状态栏可见
          win.setWindowSystemBarEnable(['status']).then(() => {
            hilog.info(DOMAIN, 'testTag', 'System bar configured');

            // 根据当前主题设置状态栏样式
            const isDark = AppStorage.get<boolean>(APP_STORAGE_KEY_SYSTEM_DARK_MODE) ?? true;
            this.updateStatusBarProperties(win, isDark);
          });
        });
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'Failed to setup immersive layout. Cause: %{public}s', error.message);
    }
  }

  // 更新状态栏样式（根据深色模式）
  private updateStatusBarStyle(isDark: boolean): void {
    try {
      const win = AppStorage.get<window.Window>(APP_STORAGE_KEY_WINDOW);
      if (win) {
        this.updateStatusBarProperties(win, isDark);
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'Failed to update status bar style. Cause: %{public}s', error.message);
    }
  }

  // 更新状态栏属性
  private updateStatusBarProperties(win: window.Window, isDark: boolean): void {
    try {
      const properties: window.SystemBarProperties = {
        statusBarColor: '#00000000', // 透明背景
        // 深色模式用白色图标，浅色模式用黑色图标
        isStatusBarLightIcon: isDark
      };

      win.setWindowSystemBarProperties(properties).then(() => {
        hilog.info(DOMAIN, 'testTag', 'Status bar properties updated, isDark: %{public}s', isDark.toString());
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'Failed to set status bar properties. Cause: %{public}s', error.message);
    }
  }

  onWindowStageDestroy(): void {
    // 主窗口被销毁，释放UI相关资源
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
    this.windowStage = null;
  }

  onForeground(): void {
    // Ability从后台回到前台
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // 更新系统深色模式状态（确保从后台回到前台时同步）
    this.updateSystemDarkMode();
    // 更新状态栏样式
    const isDark = AppStorage.get<boolean>(APP_STORAGE_KEY_SYSTEM_DARK_MODE) ?? true;
    this.updateStatusBarStyle(isDark);
  }

  onBackground(): void {
    // Ability从前台退到后台
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  // 检查定位权限状态的方法（不自动申请）
  private async checkLocationPermissions(): Promise<void> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      
      // 获取应用的tokenID（通过bundleManager获取）
      const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const tokenID = bundleInfo.appInfo.accessTokenId;

      // 检查每个权限的状态
      for (const permission of LOCATION_PERMISSIONS) {
        const grantStatus = await atManager.checkAccessToken(tokenID, permission);
        hilog.info(DOMAIN, 'testTag', 'Permission %{public}s status: %{public}d', permission, grantStatus);
      }

    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'Failed to check location permissions: %{public}s', error.message);
    }
  }

  // 公开的权限申请方法（由页面组件在用户操作时调用）
  public async requestLocationPermissions(): Promise<PermissionRequestResult> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      return await atManager.requestPermissionsFromUser(this.context, LOCATION_PERMISSIONS);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'Failed to request location permissions: %{public}s', error.message);
      throw new Error(`Failed to request location permissions: ${error.message}`);
    }
  }
}