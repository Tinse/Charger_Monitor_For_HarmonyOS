// Index.ets - 主页面
import { ChargerConfig } from './ChargerModels';
import { ConfigService } from './services/ConfigService';
import { ThemeManager, ThemeMode, ThemeColors } from './theme/ThemeManager';
import { AppStateKeys } from './AppState';
import { ChargerMonitorUI } from './components/ChargerMonitorUI';
import { SettingsUI } from './components/SettingsUI';
import { StationPickerUI } from './components/StationPickerUI';
import { MapViewerUI } from './components/MapViewerUI';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';

// 窗口实例存储 key
const APP_STORAGE_KEY_WINDOW = AppStateKeys.WINDOW;

// HdsTabs 控制器
let tabsController: HdsTabsController = new HdsTabsController();

@Entry
@Component
struct MainApp {
  private pathStack: NavPathStack = new NavPathStack();
  @State activeTab: number = 0;
  @State pickerVisible: boolean = false;
  @State configRevision: number = 0;

  // 全局共享的站点配置
  @State stationConfig: Record<string, number> = ConfigService.getDefaultConfig();
  @State monitorVisible: boolean = true;
  @State settingsVisible: boolean = false;

  // 配置变更监听器引用（用于注销）
  private configListener = (config: Record<string, number>, _configObj: ChargerConfig | null) => {
    this.stationConfig = config;
    this.configRevision++;
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
      SymbolGlyph(index === 0 ? $r('sys.symbol.bolt_1') : index === 1 ? $r('sys.symbol.map') : $r('sys.symbol.gearshape'))
        .fontSize(24).fontColor([this.activeTab === index ? this.theme.accent : this.theme.textSecondary])
      Text(title)
        .fontSize(11).fontColor(this.activeTab === index ? this.theme.accent : this.theme.textSecondary)
        .margin({ top: 4 })
    }
    .justifyContent(FlexAlign.Center)
    .height('100%')
    .width('100%')
  }

  @Builder
  tabContents() {
    // Tab 1: 监控
    TabContent() {
      ChargerMonitorUI({
        stationConfig: this.stationConfig,
        isActive: this.monitorVisible && !this.pickerVisible,
        theme: this.theme
      })
    }
    .tabBar(this.tabBuilder(0, '监控'))
    .onWillShow(() => { this.monitorVisible = true; })
    .onWillHide(() => { this.monitorVisible = false; })

    // Tab 2: 地图
    TabContent() {
      MapViewerUI({ theme: this.theme })
    }
    .tabBar(this.tabBuilder(1, '地图'))

    // Tab 3: 设置
    TabContent() {
      SettingsUI({
        isActive: this.settingsVisible && !this.pickerVisible,
        revision: this.configRevision,
        onAdd: () => { this.pathStack.pushPath({ name: 'StationPicker' }); },
        theme: this.theme,
        themeMode: this.themeMode,
        hdsImmersiveEnabled: this.hdsImmersiveEnabled,
        onImmersiveChange: (enabled: boolean) => { this.hdsImmersiveEnabled = enabled; },
        onThemeChange: (mode: ThemeMode) => {
          this.setThemeMode(mode);
        }
      })
    }
    .tabBar(this.tabBuilder(2, '设置'))
    .onWillShow(() => { this.settingsVisible = true; })
    .onWillHide(() => { this.settingsVisible = false; })
  }

  @Builder
  mainTabs() {
    HdsTabs({ controller: tabsController }) {
      this.tabContents()
    }
    .onChange((index: number) => { this.activeTab = index; })
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

  @Builder
  destinationBuilder(name: string) {
    if (name === 'StationPicker') {
      NavDestination() {
        StationPickerUI({ isActive: this.pickerVisible, theme: this.theme,
          onSaved: () => { this.configRevision++; this.pathStack.pop(); }
        })
      }.title('增加配置').backgroundColor(this.theme.background)
        .onShown(() => { this.pickerVisible = true; })
        .onHidden(() => { this.pickerVisible = false; })
    }
  }

  build() {
    Navigation(this.pathStack) {
      this.mainTabs()
    }.navDestination(this.destinationBuilder).hideTitleBar(true).mode(NavigationMode.Stack)
    .width('100%').height('100%').backgroundColor(this.theme.background)
  }
}
