// StationPickerUI.ets - 站点选择器组件
import { StationBrief, ChargerConfig } from '../ChargerModels';
import { ConfigService } from '../services/ConfigService';
import { ThemeManager, ThemeMode, ThemeColors } from '../theme/ThemeManager';
import { ErrorHandler } from '../utils/ErrorHandler';
import { StationService } from '../services/StationService';
import { Want, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import promptAction from '@ohos.promptAction';
import { geoLocationManager } from '@kit.LocationKit';
import { SegmentedControl } from './SegmentedControl';
import { SearchBar } from './SearchBar';

@CustomDialog
struct SaveConfigDialog {
  @Prop theme: ThemeColors = {} as ThemeColors;
  @Prop selectedCount: number = 0;
  @Prop configName: string = '';
  onNameChange?: (name: string) => void;
  onConfirm?: () => void;
  onCancel?: () => void;
  controller: CustomDialogController = new CustomDialogController({ builder: () => {} });

  build() {
    Column() {
      Text('保存配置')
        .fontColor(this.theme.textPrimary)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)

      Text(`已选择 ${this.selectedCount} 个站点`)
        .fontColor(this.theme.textSecondary)
        .fontSize(14)
        .margin({ top: 8 })

      TextInput({ placeholder: '请输入配置名称', text: this.configName })
        .onChange((value: string) => {
          if (this.onNameChange) {
            this.onNameChange(value);
          }
        })
        .width('100%')
        .height(44)
        .backgroundColor(this.theme.secondaryBackground)
        .fontColor(this.theme.textPrimary)
        .margin({ top: 16 })

      Row() {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.theme.tertiaryBackground)
          .fontColor(this.theme.textPrimary)
          .onClick(() => {
            this.controller.close();
            if (this.onCancel) {
              this.onCancel();
            }
          })

        Button('保存')
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.theme.accent)
          .fontColor('#ffffff')
          .margin({ left: 12 })
          .onClick(() => {
            if (this.onConfirm) {
              this.onConfirm();
            }
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('90%')
    .padding(20)
    .backgroundColor(this.theme.cardBackground)
    .borderRadius(16)
  }
}

@Component
export struct StationPickerUI {
  @Prop stationConfig: Record<string, number> = {};
  @Link hdsImmersiveEnabled: boolean;
  onThemeChange?: (mode: ThemeMode) => void;
  @Prop theme: ThemeColors = ThemeManager.getDarkColors();
  @Prop themeMode: ThemeMode = ThemeMode.SYSTEM;

  @State allStations: StationBrief[] = [];
  @State searchText: string = "";
  private searchInputText: string = "";
  @State selectedIds: number[] = [];
  private selectedIdsMap: Record<number, boolean> = {};
  @State isLoading: boolean = false;
  @State loadingMessage: string = "正在加载站点列表…";
  @State errorMessage: string = '';
  @State locationStatus: string = "";

  @State filteredStations: StationBrief[] = [];

  private configNameInput: string = "";
  private saveDialog: CustomDialogController = new CustomDialogController({
    builder: SaveConfigDialog({
      theme: this.theme,
      selectedCount: this.selectedIds.length,
      configName: this.configNameInput,
      onNameChange: (name: string) => { this.configNameInput = name; },
      onConfirm: () => { this.confirmSaveConfig(); },
      onCancel: () => {}
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  });

  private locationServiceStateCallback?: (state: boolean) => void;

  aboutToAppear() {
    this.loadSelectedStations();
    this.fetchAllStations();
    this.setupLocationServiceListener();
  }

  updateFilteredStations() {
    if (!this.searchText.trim()) {
      this.filteredStations = this.allStations;
    } else {
      const lowerSearchText = this.searchText.toLowerCase();
      const result: StationBrief[] = [];
      for (let i = 0; i < this.allStations.length; i++) {
        if (this.allStations[i].stationName.toLowerCase().includes(lowerSearchText)) {
          result.push(this.allStations[i]);
        }
      }
      this.filteredStations = result;
    }
  }

  aboutToDisappear() {
    if (this.locationServiceStateCallback) {
      try {
        geoLocationManager.off('locationEnabledChange', this.locationServiceStateCallback);
      } catch (error) {
        ErrorHandler.handle(error, 'StationPickerUI.aboutToDisappear');
      }
    }
  }

  setupLocationServiceListener() {
    try {
      this.locationServiceStateCallback = (state: boolean) => {
        if (state && this.allStations.length === 0 && !this.isLoading) {
          this.fetchAllStations();
        }
      };
      geoLocationManager.on('locationEnabledChange', this.locationServiceStateCallback);
    } catch (error) {
      ErrorHandler.handle(error, 'StationPickerUI.setupLocationServiceListener');
    }
  }

  loadSelectedStations() {
    this.selectedIds = Object.values(this.stationConfig);
    const newMap: Record<number, boolean> = {};
    for (let i = 0; i < this.selectedIds.length; i++) {
      newMap[this.selectedIds[i]] = true;
    }
    this.selectedIdsMap = newMap;
  }

  async fetchAllStations() {
    this.isLoading = true;
    this.errorMessage = '';
    this.loadingMessage = "正在获取位置信息…";

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await StationService.fetchNearbyStations(context);
      this.allStations = result.stations;
      this.locationStatus = result.locationStatus;

      if (result.needOpenLocationService) {
        this.showLocationServiceDialog();
      }

      if (this.allStations.length === 0 && !result.needOpenLocationService) {
        this.loadingMessage = "未找到附近充电站";
      }

      this.updateFilteredStations();
    } catch (error) {
      ErrorHandler.handle(error, 'StationPickerUI.fetchAllStations');
      this.errorMessage = "加载失败，请检查网络连接";
    }
    this.isLoading = false;
  }

  openLocationSettings() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const want: Want = {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'location_manager_settings'
      };
      context.startAbility(want)
        .then(() => {
          console.log('Opened location settings');
        })
        .catch((err: BusinessError) => {
          ErrorHandler.handle(err, 'StationPickerUI.openLocationSettings');
        });
    } catch (error) {
      ErrorHandler.handle(error, 'StationPickerUI.openLocationSettings');
    }
  }

  toggleStation(stationId: number) {
    const index = this.selectedIds.indexOf(stationId);
    if (index > -1) {
      this.selectedIds = this.selectedIds.filter(id => id !== stationId);
      const newMap: Record<number, boolean> = {};
      const keys = Object.keys(this.selectedIdsMap);
      for (let i = 0; i < keys.length; i++) {
        const key = parseInt(keys[i]);
        if (key !== stationId) {
          newMap[key] = true;
        }
      }
      this.selectedIdsMap = newMap;
    } else {
      this.selectedIds = [...this.selectedIds, stationId];
      const newMap: Record<number, boolean> = {};
      const keys = Object.keys(this.selectedIdsMap);
      for (let i = 0; i < keys.length; i++) {
        newMap[parseInt(keys[i])] = true;
      }
      newMap[stationId] = true;
      this.selectedIdsMap = newMap;
    }
  }

  selectAllStations() {
    const newSelectedIds: number[] = [];
    const newSelectedIdsMap: Record<number, boolean> = {};
    const stations = this.filteredStations;
    for (let i = 0; i < stations.length; i++) {
      newSelectedIds.push(stations[i].stationId);
      newSelectedIdsMap[stations[i].stationId] = true;
    }
    this.selectedIdsMap = newSelectedIdsMap;
    this.selectedIds = newSelectedIds;
  }

  deselectAllStations() {
    this.selectedIds = [];
    this.selectedIdsMap = {};
  }

  isStationSelected(stationId: number): boolean {
    return this.selectedIdsMap[stationId] === true;
  }

  getFilteredStations(): StationBrief[] {
    return this.filteredStations;
  }

  async saveConfig() {
    if (this.selectedIds.length === 0) {
      ErrorHandler.showToast(this.getUIContext(), '请至少选择一个站点');
      return;
    }

    const newConfig: Record<string, number> = {};
    this.allStations
      .filter(station => this.selectedIds.includes(station.stationId))
      .forEach(station => {
        newConfig[station.stationName] = station.stationId;
      });

    if (Object.keys(newConfig).length === 0) {
      ErrorHandler.showToast(this.getUIContext(), '站点列表加载失败，请检查网络和权限设置', 3000);
      return;
    }

    this.configNameInput = `我的配置 ${new Date().toLocaleTimeString()}`;
    this.saveDialog.open();
  }

  async confirmSaveConfig() {
    if (this.configNameInput.trim() === '') {
      ErrorHandler.showToast(this.getUIContext(), '请输入配置名称');
      return;
    }

    const newConfig: Record<string, number> = {};
    this.allStations
      .filter(station => this.selectedIds.includes(station.stationId))
      .forEach(station => {
        newConfig[station.stationName] = station.stationId;
      });

    try {
      await ConfigService.addConfig(this.configNameInput.trim(), newConfig);
      ErrorHandler.showToast(this.getUIContext(), `已保存 ${this.selectedIds.length} 个站点`);
      this.saveDialog.close();
    } catch (error) {
      ErrorHandler.handle(error, 'StationPickerUI.confirmSaveConfig');
      ErrorHandler.showToast(this.getUIContext(), '保存配置失败');
    }
  }

  showLocationServiceDialog() {
    promptAction.showDialog({
      title: '需要开启定位服务',
      message: '请前往系统设置开启位置服务，以获取附近的充电站信息',
      buttons: [
        { text: '取消', color: '#8e8e93' },
        { text: '去设置', color: '#30d158' }
      ]
    }).then((data: promptAction.ShowDialogSuccessResponse) => {
      if (data.index === 1) {
        this.openLocationSettings();
      }
    }).catch((err: BusinessError) => {
      ErrorHandler.handle(err, 'StationPickerUI.showLocationServiceDialog');
    });
  }

  build() {
    Column() {
      Scroll() {
        Column() {

          // 1. 个人资料卡片
          Row() {
            Column() {
              Text('充电桩监控')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.theme.textPrimary)

              Text(`v1.4 · 已配置 ${Object.keys(this.stationConfig).length} 个站点`)
                .fontSize(12)
                .fontColor(this.theme.textSecondary)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
          }
          .width('90%')
          .padding(16)
          .backgroundColor(this.theme.cardBackground)
          .borderRadius(16)
          .margin({ top: 16, bottom: 8 })

          // 2. 外观设置分组
          // 分组标题
          Text('外观')
            .fontSize(12)
            .fontColor(this.theme.textSecondary)
            .fontWeight(FontWeight.Normal)
            .padding({ left: 16, right: 16, top: 8, bottom: 4 })
            .width('90%')

          // 设置卡片
          Column() {
            // 主题模式行
            Row() {
              Text('🎨')
                .fontSize(20)
                .width(28)
                .textAlign(TextAlign.Center)
                .margin({ right: 12 })

              Column() {
                Text('主题模式')
                  .fontSize(15)
                  .fontColor(this.theme.textPrimary)
                  .fontWeight(FontWeight.Normal)

                Text(this.themeMode === ThemeMode.SYSTEM ? '跟随系统' : (this.themeMode === ThemeMode.DARK ? '深色模式' : '浅色模式'))
                  .fontSize(12)
                  .fontColor(this.theme.textSecondary)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 8 })

            // 分段控件
            SegmentedControl({
              segments: [
                { label: '跟随系统', value: ThemeMode.SYSTEM },
                { label: '深色', value: ThemeMode.DARK },
                { label: '浅色', value: ThemeMode.LIGHT }
              ],
              selectedIndex: this.themeMode === ThemeMode.SYSTEM ? 0 : (this.themeMode === ThemeMode.DARK ? 1 : 2),
              theme: this.theme,
              onChangeCallback: (_: number, value: number) => {
                if (this.onThemeChange) {
                  this.onThemeChange(value as ThemeMode);
                }
              }
            })
            .margin({ left: 16, right: 16, bottom: 12 })

            // 分隔线
            Divider()
              .color(this.theme.border)
              .margin({ left: 56, right: 16 })

            // HDS 沉浸光感行
            Row() {
              Text('✨')
                .fontSize(20)
                .width(28)
                .textAlign(TextAlign.Center)
                .margin({ right: 12 })

              Column() {
                Text('HDS 沉浸光感')
                  .fontSize(15)
                  .fontColor(this.theme.textPrimary)
                  .fontWeight(FontWeight.Normal)

                Text('底部导航栏玻璃质感效果')
                  .fontSize(12)
                  .fontColor(this.theme.textSecondary)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.hdsImmersiveEnabled })
                .onChange((isOn: boolean) => {
                  this.hdsImmersiveEnabled = isOn;
                })
                .selectedColor(this.theme.accent)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          }
          .width('90%')
          .backgroundColor(this.theme.cardBackground)
          .borderRadius(12)
          .clip(true)
          .margin({ bottom: 16 })

          // 3. 站点配置分组
          Text('站点配置')
            .fontSize(12)
            .fontColor(this.theme.textSecondary)
            .fontWeight(FontWeight.Normal)
            .padding({ left: 16, right: 16, top: 8, bottom: 4 })
            .width('90%')

          Column() {
            // 搜索栏
            SearchBar({
              placeholder: '搜索站点名称…',
              value: this.searchInputText,
              theme: this.theme,
              onChangeCallback: (value: string) => {
                this.searchInputText = value;
              },
              onSubmitCallback: (value: string) => {
                this.searchText = this.searchInputText;
                this.updateFilteredStations();
              }
            })
            .margin({ left: 16, right: 16, top: 12, bottom: 8 })

            // 全选/全不选
            Row() {
              Text(`已选择 ${this.selectedIds.length} 个站点`)
                .fontColor(this.theme.textSecondary)
                .fontSize(13)

              Blank()

              Button('全选')
                .fontSize(12)
                .height(28)
                .backgroundColor(this.theme.secondaryBackground)
                .fontColor(this.theme.textPrimary)
                .borderRadius(6)
                .onClick(() => {
                  this.selectAllStations();
                })

              Button('全不选')
                .fontSize(12)
                .height(28)
                .backgroundColor(this.theme.secondaryBackground)
                .fontColor(this.theme.textPrimary)
                .borderRadius(6)
                .margin({ left: 8 })
                .onClick(() => {
                  this.deselectAllStations();
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })

            // 位置状态提示
            if (this.locationStatus) {
              Text(this.locationStatus)
                .fontColor(this.theme.textSecondary)
                .fontSize(12)
                .padding({ left: 16, right: 16, bottom: 8 })
            }

            // 加载状态
            if (this.isLoading) {
              Row() {
                LoadingProgress()
                  .width(24)
                  .height(24)
                Text(this.loadingMessage)
                  .fontColor(this.theme.textPrimary)
                  .fontSize(14)
                  .margin({ left: 10 })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding(20)
            } else if (this.allStations.length === 0) {
              Column({ space: 12 }) {
                if (this.errorMessage) {
                  // 错误状态
                  Text('加载失败')
                    .fontColor(this.theme.error)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                  Text(this.errorMessage)
                    .fontColor(this.theme.textSecondary)
                    .fontSize(14)
                    .textAlign(TextAlign.Center)
                } else {
                  // 空状态
                  Text('未找到附近充电站')
                    .fontColor(this.theme.textPrimary)
                    .fontSize(16)
                  if (this.locationStatus.includes('默认位置')) {
                    Text('请确保设备定位服务已开启')
                      .fontColor(this.theme.textSecondary)
                      .fontSize(14)
                  }
                  if (this.locationStatus.includes('网络')) {
                    Text('请检查网络连接')
                      .fontColor(this.theme.textSecondary)
                      .fontSize(14)
                  }
                }
                Button(this.errorMessage ? '重试' : '刷新')
                  .backgroundColor(this.theme.accent)
                  .fontColor('#ffffff')
                  .width(120)
                  .height(40)
                  .onClick(() => {
                    StationService.clearCache();
                    this.fetchAllStations();
                  })
              }
              .width('100%')
              .padding(20)
            } else {
              // 站点列表
              ForEach(this.getFilteredStations(), (station: StationBrief) => {
                Column() {
                  Row() {
                    Checkbox({
                      name: station.stationName,
                      group: 'stations'
                    })
                    .select(this.isStationSelected(station.stationId))
                    .onChange((checked: boolean) => {
                      this.toggleStation(station.stationId);
                    })
                    .size({ width: 20, height: 20 })
                    .margin({ right: 12 })

                    Column({ space: 2 }) {
                      Text(station.stationName)
                        .fontColor(this.theme.textPrimary)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)

                      if (station.address) {
                        Text(station.address)
                          .fontColor(this.theme.textSecondary)
                          .fontSize(12)
                      }

                      if (station.formattedDistance) {
                        Text(`距离: ${station.formattedDistance}`)
                          .fontColor(this.theme.success)
                          .fontSize(11)
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 12, bottom: 12 })

                  Divider()
                    .color(this.theme.border)
                    .margin({ left: 48, right: 16 })
                }
              }, (station: StationBrief) => station.stationId.toString())
            }
          }
          .width('90%')
          .backgroundColor(this.theme.cardBackground)
          .borderRadius(12)
          .clip(true)

          // 4. 保存按钮
          Button(`保存选中站点 (${this.selectedIds.length})`)
            .width('90%')
            .height(44)
            .margin({ top: 16, bottom: 120 })
            .backgroundColor(this.selectedIds.length > 0 ? this.theme.accent : this.theme.tertiaryBackground)
            .fontColor('#ffffff')
            .borderRadius(12)
            .onClick(() => this.saveConfig())
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }
}
