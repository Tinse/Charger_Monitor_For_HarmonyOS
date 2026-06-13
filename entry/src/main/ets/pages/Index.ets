// Index.ets - 主页面
import { ChargerConfig } from './ChargerModels';
import { ConfigService } from './services/ConfigService';
import { ThemeManager, ThemeMode, ThemeColors } from './theme/ThemeManager';
import { ErrorHandler } from './utils/ErrorHandler';
import { AppStateKeys } from './AppState';
import { ChargerMonitorUI } from './components/ChargerMonitorUI';
import { StationPickerUI } from './components/StationPickerUI';
import { MapViewerUI } from './components/MapViewerUI';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';

// 窗口实例存储 key
const APP_STORAGE_KEY_WINDOW = 'app.window';

// HdsTabs 控制器
let tabsController: HdsTabsController = new HdsTabsController();

@Entry
@Component
struct MainApp {
  // 全局共享的站点配置
  @State stationConfig: Record<string, number> = ConfigService.getDefaultConfig();

  // 配置变更监听器引用（用于注销）
  private configListener = (config: Record<string, number>, _configObj: ChargerConfig | null) => {
    this.stationConfig = config;
  };

  // 主题相关状态
  @State themeMode: ThemeMode = ThemeMode.SYSTEM;
  @StorageLink(AppStateKeys.SYSTEM_DARK_MODE) @Watch('onSystemDarkModeChange') systemDarkMode: boolean = true;
  @State theme: ThemeColors = ThemeManager.getDarkColors();

  // HDS 沉浸光感开关
  @State hdsImmersiveEnabled: boolean = true;

  // 系统深色模式变化回调
  onSystemDarkModeChange(): void {
    this.updateThemeColors();
  }

  // 更新主题颜色
  updateThemeColors(): void {
    const isDark = ThemeManager.resolveIsDark(this.themeMode, this.systemDarkMode);
    this.theme = ThemeManager.getColors(isDark);
    this.updateStatusBarStyle(isDark);
  }

  // 更新状态栏样式
  private updateStatusBarStyle(isDark: boolean): void {
    try {
      const win = AppStorage.get<window.Window>(APP_STORAGE_KEY_WINDOW);
      if (win) {
        const properties: window.SystemBarProperties = {
          statusBarColor: '#00000000',
          isStatusBarLightIcon: isDark
        };
        win.setWindowSystemBarProperties(properties);
      }
    } catch (error) {
      console.error('Failed to update status bar style:', error);
    }
  }

  // 切换主题模式
  async setThemeMode(mode: ThemeMode): Promise<void> {
    this.themeMode = mode;
    this.updateThemeColors();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await ThemeManager.applyThemeMode(context, mode);
  }

  async aboutToAppear() {
    // 加载当前配置
    this.stationConfig = await ConfigService.getCurrentStationConfig();
    // 注册配置变更监听
    ConfigService.addListener(this.configListener);
    this.initTheme();
  }

  aboutToDisappear() {
    ConfigService.removeListener(this.configListener);
  }

  // 初始化主题
  async initTheme() {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.themeMode = await ThemeManager.loadThemeMode(context);
    await ThemeManager.applyThemeMode(context, this.themeMode);
    this.updateThemeColors();
  }

  // 自定义 TabBar 构建器
  @Builder
  tabBuilder(index: number, title: string) {
    Column() {
      Text(index === 0 ? '📊' : index === 1 ? '🗺️' : '⚙️')
        .fontSize(24)
      Text(title)
        .fontSize(12)
        .margin({ top: 4 })
    }
    .justifyContent(FlexAlign.Center)
    .height('100%')
    .width('100%')
  }

  build() {
    Column() {
      // 使用 HdsTabs 实现沉浸光感底部页签
      HdsTabs({ controller: tabsController }) {
        // Tab 1: 监控
        TabContent() {
          ChargerMonitorUI({
            stationConfig: this.stationConfig,
            theme: this.theme
          })
        }
        .tabBar(this.tabBuilder(0, '监控'))

        // Tab 2: 地图
        TabContent() {
          MapViewerUI({ theme: this.theme })
        }
        .tabBar(this.tabBuilder(1, '地图'))

        // Tab 3: 设置
        TabContent() {
          StationPickerUI({
            stationConfig: this.stationConfig,
            theme: this.theme,
            themeMode: this.themeMode,
            hdsImmersiveEnabled: $hdsImmersiveEnabled,
            onThemeChange: (mode: ThemeMode) => {
              this.setThemeMode(mode);
            }
          })
        }
        .tabBar(this.tabBuilder(2, '设置'))
      }
      // 设置底部页签悬浮样式 - 启用沉浸光感
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .barFloatingStyle(this.hdsImmersiveEnabled ? {
        barWidth: { smallWidth: 280, mediumWidth: 320, largeWidth: 360 },
        barBottomMargin: 28,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      } : {
        barWidth: { smallWidth: 280, mediumWidth: 320, largeWidth: 360 },
        barBottomMargin: 28
      })
    }
    .width('100%').height('100%').backgroundColor(this.theme.background)
  }
}