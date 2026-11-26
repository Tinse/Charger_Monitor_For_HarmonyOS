// Index.ets - 主页面
import { ChargerConfig } from './ChargerModels';
import { ConfigService } from './services/ConfigService';
import { ThemeManager, ThemeMode, ThemeColors } from './theme/ThemeManager';
import { AppStateKeys } from './AppState';
import { ChargerMonitorUI } from './components/ChargerMonitorUI';
import { SettingsUI } from './components/SettingsUI';
import { ConfigDetailUI } from './components/ConfigDetailUI';
import { StationPickerUI } from './components/StationPickerUI';
import { MapViewerUI } from './components/MapViewerUI';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { ErrorHandler } from './utils/ErrorHandler';
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
  @State tabsVisible: boolean = true;
  @StorageProp(AppStateKeys.FOREGROUND) foreground: boolean = false;
  @State pickerSeed: ChargerConfig | null = null;
  @State pickerEditId: string = '';
  @State pickerHasChanges: boolean = false;
  private discardDialogOpen: boolean = false;
  @State configRevision: number = 0;
  @State configReady: boolean = false;
  @State configReadError: boolean = false;
  private configReadVersion: number = 0;

  // 全局共享的站点配置
  @State stationConfig: Record<string, number> = {};
  @State monitorVisible: boolean = true;
  @State settingsVisible: boolean = false;

  // 配置变更监听器引用（用于注销）
  private configListener = (config: Record<string, number>, _configObj: ChargerConfig | null) => {
    this.configReadVersion++;
    this.stationConfig = config;
    this.configReady = true;
    this.configReadError = false;
    this.configRevision++;
  };

  // 主题相关状态
  @State themeMode: ThemeMode = ThemeMode.SYSTEM;
  @StorageLink(AppStateKeys.SYSTEM_DARK_MODE) @Watch('onSystemDarkModeChange') systemDarkMode: boolean = true;
  @State theme: ThemeColors = ThemeManager.getDarkColors();

  // HDS 沉浸光感开关
  @State hdsImmersiveEnabled: boolean = true;
  @State appearanceBusy: boolean = true;

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
        win.setWindowSystemBarProperties(properties).catch((error: BusinessError) => {
          ErrorHandler.handle(error, 'MainApp.updateStatusBarStyle');
        });
      }
    } catch (error) {
      console.error('Failed to update status bar style:', error);
    }
  }

  // 切换主题模式
  async setThemeMode(mode: ThemeMode): Promise<void> {
    if (this.appearanceBusy || this.themeMode === mode) return;
    this.appearanceBusy = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await ThemeManager.changeThemeMode(context, mode, this.themeMode);
      this.themeMode = mode;
      this.updateThemeColors();
    } catch (error) {
      ErrorHandler.showToast(this.getUIContext(), '主题设置失败，请重试');
    } finally { this.appearanceBusy = false; }
  }

  async setImmersiveEnabled(enabled: boolean) {
    if (this.appearanceBusy || this.hdsImmersiveEnabled === enabled) return;
    this.appearanceBusy = true;
    const previous = this.hdsImmersiveEnabled;
    this.hdsImmersiveEnabled = enabled;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await ThemeManager.saveImmersiveEnabled(context, enabled, previous);
    } catch (error) {
      this.hdsImmersiveEnabled = previous;
      ErrorHandler.showToast(this.getUIContext(), '外观设置保存失败，请重试');
    } finally { this.appearanceBusy = false; }
  }

  aboutToAppear() {
    ConfigService.addListener(this.configListener);
    this.loadStationConfig();
    this.initTheme();
  }

  aboutToDisappear() {
    this.configReadVersion++;
    ConfigService.removeListener(this.configListener);
  }

  private async loadStationConfig(): Promise<void> {
    const version = ++this.configReadVersion;
    this.configReadError = false;
    try {
      const config = await ConfigService.getCurrentStationConfig();
      if (version !== this.configReadVersion) return;
      this.stationConfig = config;
      this.configReady = true;
    } catch (error) {
      if (version === this.configReadVersion) this.configReadError = true;
      ErrorHandler.handle(error, 'MainApp.loadStationConfig');
    }
  }

  // 初始化主题
  async initTheme() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.themeMode = await ThemeManager.loadThemeMode(context);
      this.hdsImmersiveEnabled = await ThemeManager.loadImmersiveEnabled(context);
      ThemeManager.applyThemeMode(context, this.themeMode);
    } catch (error) {
      ErrorHandler.handle(error, 'MainApp.initTheme');
    } finally {
      this.updateThemeColors();
      this.appearanceBusy = false;
    }
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
      if (this.configReady) {
        ChargerMonitorUI({
          stationConfig: this.stationConfig,
          isActive: this.foreground && this.monitorVisible && this.tabsVisible,
          theme: this.theme,
          onManageConfig: (id: string) => {
            if (id) this.pathStack.pushPath({ name: 'ConfigDetail', param: id });
            else this.openPicker(null, false);
          }
        })
      } else if (this.configReadError) {
        Column({ space: 12 }) {
          Text('站点配置读取失败').fontSize(16).fontColor(this.theme.textPrimary)
          Button('重新读取配置').onClick(() => this.loadStationConfig())
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else {
        LoadingProgress().width(32).height(32).accessibilityText('正在读取站点配置')
      }
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
        isActive: this.foreground && this.settingsVisible && this.tabsVisible,
        revision: this.configRevision,
        onAdd: () => { this.openPicker(null, false); },
        onOpen: (id: string) => { this.pathStack.pushPath({ name: 'ConfigDetail', param: id }); },
        theme: this.theme,
        themeMode: this.themeMode,
        hdsImmersiveEnabled: this.hdsImmersiveEnabled,
        appearanceBusy: this.appearanceBusy,
        onImmersiveChange: (enabled: boolean) => { this.setImmersiveEnabled(enabled); },
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
  destinationBuilder(name: string, param: Object) {
    if (name === 'StationPicker') {
      NavDestination() {
        StationPickerUI({ isActive: this.foreground && this.pickerVisible, theme: this.theme,
          initialConfig: this.pickerSeed, editConfigId: this.pickerEditId,
          onDirtyChange: (dirty: boolean) => { this.pickerHasChanges = dirty; },
          onSaved: () => { this.pickerHasChanges = false; this.configRevision++; this.pathStack.pop(); }
        })
      }.title(this.pickerEditId ? '编辑配置' : '增加配置').backgroundColor(this.theme.background)
        .onBackPressed(() => this.confirmPickerBack())
        .onShown(() => { this.pickerVisible = true; })
        .onHidden(() => { this.pickerVisible = false; })
    } else if (name === 'ConfigDetail') {
      NavDestination() {
        ConfigDetailUI({ configId: param as string, revision: this.configRevision, theme: this.theme,
          onEdit: (config: ChargerConfig, copy: boolean) => { this.openPicker(config, !copy); },
          onDeleted: () => { this.configRevision++; this.pathStack.pop(); }
        })
      }.title('配置详情').backgroundColor(this.theme.background)
    }
  }

  openPicker(config: ChargerConfig | null, edit: boolean) {
    this.pickerSeed = config;
    this.pickerEditId = edit && config ? config.id : '';
    this.pickerHasChanges = false;
    this.pathStack.pushPath({ name: 'StationPicker' });
  }

  confirmPickerBack(): boolean {
    if (!this.pickerHasChanges) return false;
    if (this.discardDialogOpen) return true;
    this.discardDialogOpen = true;
    this.getUIContext().getPromptAction().showDialog({
      title: '放弃未保存的修改？', message: '离开后，本次修改不会保存。',
      buttons: [{ text: '继续编辑', color: this.theme.accent }, { text: '放弃修改', color: this.theme.error }]
    }).then(result => {
      if (result.index === 1) { this.pickerHasChanges = false; this.pathStack.pop(); }
    }).catch(() => {}).finally(() => { this.discardDialogOpen = false; });
    return true;
  }

  build() {
    Navigation(this.pathStack) {
      this.mainTabs()
    }.navDestination(this.destinationBuilder).hideTitleBar(true).mode(NavigationMode.Stack)
    .onNavBarStateChange((visible: boolean) => { this.tabsVisible = visible; })
    .width('100%').height('100%').backgroundColor(this.theme.background)
  }
}
