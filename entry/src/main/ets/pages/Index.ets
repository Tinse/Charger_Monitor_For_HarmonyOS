// Index.ets - 主页面
import { ChargerConfig } from './ChargerModels';
import { ConfigService } from './services/ConfigService';
import { StationService } from './services/StationService';
import { NetworkState } from './services/NetworkState';
import { ThemeManager, ThemeMode, ThemeColors } from './theme/ThemeManager';
import { AppStateKeys } from './AppState';
import { ChargerMonitorUI } from './components/ChargerMonitorUI';
import { SettingsUI } from './components/SettingsUI';
import { ConfigDetailUI } from './components/ConfigDetailUI';
import { ConfigStationUI } from './components/ConfigStationUI';
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

interface StationRoute {
  configId: string;
  stationId: number;
}

interface PickerRoute {
  mode: string;
  config: ChargerConfig | null;
  replaceStationId: number;
}

@Entry
@Component
struct MainApp {
  private pathStack: NavPathStack = new NavPathStack();
  @State activeTab: number = 0;
  @State pickerVisible: boolean = false;
  @State tabsVisible: boolean = true;
  @StorageProp(AppStateKeys.FOREGROUND) @Watch('onForegroundChanged') foreground: boolean = false;
  @State networkOnline: boolean = false;
  @State networkRevision: number = 0;
  private network: NetworkState = new NetworkState();
  private draftChanged: boolean = false;
  private writePending: boolean = false;
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
    this.network.start((online: boolean) => {
      if (online === this.networkOnline) return;
      this.networkOnline = online;
      this.networkRevision++;
    });
    ConfigService.addListener(this.configListener);
    this.loadStationConfig();
    this.initTheme();
  }

  aboutToDisappear() {
    this.network.stop();
    this.configReadVersion++;
    ConfigService.removeListener(this.configListener);
  }

  onForegroundChanged() {
    if (this.foreground) this.network.refresh();
  }

  private async loadStationConfig(): Promise<void> {
    const version = ++this.configReadVersion;
    this.configReadError = false;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await StationService.initSnapshots(context.getApplicationContext());
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
        .fontSize(22).fontColor([this.activeTab === index ? this.theme.accent : this.theme.textSecondary])
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
          configRevision: this.configRevision,
          networkOnline: this.networkOnline,
          networkRevision: this.networkRevision,
          isActive: this.foreground && this.monitorVisible && this.tabsVisible,
          theme: this.theme,
          onAddStations: (config: ChargerConfig) => { this.openPicker('add', config); },
          onManageConfig: (id: string) => {
            if (id) this.openDetail(id);
            else this.openPicker('create', null);
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
        onAdd: () => { this.openPicker('create', null); },
        onOpen: (id: string) => { this.openDetail(id); },
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
      barBottomMargin: 20,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    } : {
      barWidth: { smallWidth: 280, mediumWidth: 320, largeWidth: 360 },
      barBottomMargin: 20
    })
  }

  @Builder
  destinationBuilder(name: string, param: Object) {
    if (name === 'StationPicker') {
      NavDestination() {
        StationPickerUI({ isActive: this.foreground && this.pickerVisible, theme: this.theme,
          initialConfig: (param as PickerRoute).config, mode: (param as PickerRoute).mode,
          replaceStationId: (param as PickerRoute).replaceStationId,
          onDirtyChange: (dirty: boolean) => { this.markDirty(name, dirty); },
          onBusyChange: (busy: boolean) => { this.markBusy(name, busy); },
          onSaved: (openCreatedId?: string) => {
            this.finishChange(name, (param as PickerRoute).mode === 'replace');
            if (openCreatedId) this.openDetail(openCreatedId);
          }
        })
      }.title(this.pickerTitle((param as PickerRoute).mode)).backgroundColor(this.theme.background)
        .onBackPressed(() => this.confirmBack(name))
        .onShown(() => { this.pickerVisible = true; })
        .onHidden(() => { this.pickerVisible = false; })
    } else if (name === 'ConfigDetail') {
      NavDestination() {
        ConfigDetailUI({ configId: param as string, revision: this.configRevision, theme: this.theme,
          onAddStations: (config: ChargerConfig) => { this.openPicker('add', config); },
          onOpenStation: (config: ChargerConfig, id: number) => { this.openStation(config.id, id); },
          onCopy: (config: ChargerConfig) => { this.openPicker('copy', config); },
          onDirtyChange: (dirty: boolean) => { this.markDirty(name, dirty); },
          onBusyChange: (busy: boolean) => { this.markBusy(name, busy); },
          onChanged: () => { this.configRevision++; },
          onDeleted: () => { this.finishChange(name); }
        })
      }.title('配置详情').backgroundColor(this.theme.background)
        .onBackPressed(() => this.confirmBack(name))
    } else if (name === 'ConfigStation') {
      NavDestination() {
        ConfigStationUI({ configId: (param as StationRoute).configId, stationId: (param as StationRoute).stationId,
          revision: this.configRevision, theme: this.theme,
          onReplace: (config: ChargerConfig, id: number) => { this.openPicker('replace', config, id); },
          onDirtyChange: (dirty: boolean) => { this.markDirty(name, dirty); },
          onBusyChange: (busy: boolean) => { this.markBusy(name, busy); },
          onChanged: () => { this.configRevision++; },
          onRemoved: () => { this.finishChange(name); }
        })
      }.title('站点详情').backgroundColor(this.theme.background)
        .onBackPressed(() => this.confirmBack(name))
    }
  }

  private pickerTitle(mode: string): string {
    if (mode === 'add') return '添加站点';
    if (mode === 'replace') return '替换站点';
    if (mode === 'copy') return '复制配置';
    return '增加配置';
  }

  private resetEditorState(): void {
    this.draftChanged = false;
    this.writePending = false;
  }

  private openDetail(configId: string): void {
    this.resetEditorState();
    this.pathStack.pushPath({ name: 'ConfigDetail', param: configId });
  }

  private openStation(configId: string, stationId: number): void {
    const route: StationRoute = { configId, stationId };
    this.resetEditorState();
    this.pathStack.pushPath({ name: 'ConfigStation', param: route });
  }

  private openPicker(mode: string, config: ChargerConfig | null, replaceStationId: number = 0): void {
    const route: PickerRoute = { mode, config, replaceStationId };
    this.resetEditorState();
    this.pathStack.pushPath({ name: 'StationPicker', param: route });
  }

  private isTop(name: string): boolean {
    const names = this.pathStack.getAllPathName();
    return names.length > 0 && names[names.length - 1] === name;
  }

  private markDirty(name: string, dirty: boolean): void {
    if (this.isTop(name)) this.draftChanged = dirty;
  }

  private markBusy(name: string, busy: boolean): void {
    if (this.isTop(name)) this.writePending = busy;
  }

  private finishChange(name: string, returnToConfig: boolean = false): void {
    this.configRevision++;
    if (!this.isTop(name)) return;
    this.resetEditorState();
    if (returnToConfig) this.pathStack.popToName('ConfigDetail');
    else this.pathStack.pop();
  }

  private confirmBack(name: string): boolean {
    if (this.writePending || this.discardDialogOpen) return true;
    if (!this.draftChanged) return false;
    this.discardDialogOpen = true;
    this.getUIContext().getPromptAction().showDialog({
      title: '放弃未保存的修改？', message: '离开后，本次修改不会保存。',
      buttons: [{ text: '继续编辑', color: this.theme.accent }, { text: '放弃修改', color: this.theme.error }]
    }).then(result => {
      if (result.index === 1 && this.isTop(name)) {
        this.resetEditorState();
        this.pathStack.pop();
      }
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
