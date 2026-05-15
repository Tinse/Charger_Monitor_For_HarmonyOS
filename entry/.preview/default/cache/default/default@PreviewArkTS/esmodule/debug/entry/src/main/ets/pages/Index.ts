if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface MapViewerUI_Params {
    scaleValue?: number;
    pinchValue?: number;
    offsetX?: number;
    offsetY?: number;
    lastOffsetX?: number;
    lastOffsetY?: number;
    minScale?: number;
    maxScale?: number;
}
interface StationPickerUI_Params {
    stationConfig?: Record<string, number>;
    // 保存配置的回调函数
    onSaveConfig?: (newConfig: Record<string, number>) => void;
    allStations?: StationBrief[];
    searchText?: string;
    selectedIds?: number[];
    isLoading?: boolean;
    loadingMessage?: string;
    locationStatus?: string;
    locationServiceStateCallback?: (state: boolean) => void;
}
interface ChargerMonitorUI_Params {
    stationConfig?: Record<string, number>;
    configs?: ChargerConfig[];
    currentConfig?: ChargerConfig | null;
    isExpanded?: boolean;
    stations?: StationData[];
    searchText?: string;
    sortMode?: number;
    showSortMenu?: boolean;
    isLoading?: boolean;
    showConfigList?: boolean;
    canRefresh?: boolean;
    refreshCooldown?: number;
    screenHeight?: number;
    refreshInterval?: number;
    lastConfigHash?: string;
    cooldownInterval?: number;
}
interface MainApp_Params {
    stationConfig?: Record<string, number>;
    configs?: ChargerConfig[];
    currentConfig?: ChargerConfig | null;
    showConfigDialog?: boolean;
    configDialogText?: string;
    showConfigList?: boolean;
    pendingConfig?: Record<string, number>;
}
import { ChargerApi } from "@normalized:N&&&entry/src/main/ets/pages/ChargerApi&";
import { SORT_MODE } from "@normalized:N&&&entry/src/main/ets/pages/ChargerModels&";
import type { StationData, OutletDetail, StationBrief, ChargerConfig } from "@normalized:N&&&entry/src/main/ets/pages/ChargerModels&";
import { ConfigManager } from "@normalized:N&&&entry/src/main/ets/pages/ConfigManager&";
import type common from "@ohos:app.ability.common";
import promptAction from "@ohos:promptAction";
import display from "@ohos:display";
import geoLocationManager from "@ohos:geoLocationManager";
import type Want from "@ohos:app.ability.Want";
import type { BusinessError } from "@ohos:base";
interface StatsResult {
    total: number;
    free: number;
    anyFree: boolean;
}
interface StationWithFreeCount {
    station: StationData;
    freeCount: number;
}
class MainApp extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__stationConfig = new ObservedPropertyObjectPU(ConfigManager.getDefaultConfig(), this, "stationConfig");
        this.__configs = new ObservedPropertyObjectPU([], this, "configs");
        this.__currentConfig = new ObservedPropertyObjectPU(null, this, "currentConfig");
        this.__showConfigDialog = new ObservedPropertySimplePU(false, this, "showConfigDialog");
        this.__configDialogText = new ObservedPropertySimplePU("", this, "configDialogText");
        this.__showConfigList = new ObservedPropertySimplePU(false, this, "showConfigList");
        this.__pendingConfig = new ObservedPropertyObjectPU({}, this, "pendingConfig");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: MainApp_Params) {
        if (params.stationConfig !== undefined) {
            this.stationConfig = params.stationConfig;
        }
        if (params.configs !== undefined) {
            this.configs = params.configs;
        }
        if (params.currentConfig !== undefined) {
            this.currentConfig = params.currentConfig;
        }
        if (params.showConfigDialog !== undefined) {
            this.showConfigDialog = params.showConfigDialog;
        }
        if (params.configDialogText !== undefined) {
            this.configDialogText = params.configDialogText;
        }
        if (params.showConfigList !== undefined) {
            this.showConfigList = params.showConfigList;
        }
        if (params.pendingConfig !== undefined) {
            this.pendingConfig = params.pendingConfig;
        }
    }
    updateStateVars(params: MainApp_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__stationConfig.purgeDependencyOnElmtId(rmElmtId);
        this.__configs.purgeDependencyOnElmtId(rmElmtId);
        this.__currentConfig.purgeDependencyOnElmtId(rmElmtId);
        this.__showConfigDialog.purgeDependencyOnElmtId(rmElmtId);
        this.__configDialogText.purgeDependencyOnElmtId(rmElmtId);
        this.__showConfigList.purgeDependencyOnElmtId(rmElmtId);
        this.__pendingConfig.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__stationConfig.aboutToBeDeleted();
        this.__configs.aboutToBeDeleted();
        this.__currentConfig.aboutToBeDeleted();
        this.__showConfigDialog.aboutToBeDeleted();
        this.__configDialogText.aboutToBeDeleted();
        this.__showConfigList.aboutToBeDeleted();
        this.__pendingConfig.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    // 辅助方法：显示Toast消息（API 18+兼容）
    private showToast(message: string, duration: number = 2000): void {
        try {
            this.getUIContext().getPromptAction().openToast({
                message: message,
                duration: duration
            });
        }
        catch (error) {
            console.error('Failed to show toast:', error);
        }
    }
    // 全局共享的站点配置
    private __stationConfig: ObservedPropertyObjectPU<Record<string, number>>;
    get stationConfig() {
        return this.__stationConfig.get();
    }
    set stationConfig(newValue: Record<string, number>) {
        this.__stationConfig.set(newValue);
    }
    private __configs: ObservedPropertyObjectPU<ChargerConfig[]>;
    get configs() {
        return this.__configs.get();
    }
    set configs(newValue: ChargerConfig[]) {
        this.__configs.set(newValue);
    }
    private __currentConfig: ObservedPropertyObjectPU<ChargerConfig | null>;
    get currentConfig() {
        return this.__currentConfig.get();
    }
    set currentConfig(newValue: ChargerConfig | null) {
        this.__currentConfig.set(newValue);
    }
    private __showConfigDialog: ObservedPropertySimplePU<boolean>;
    get showConfigDialog() {
        return this.__showConfigDialog.get();
    }
    set showConfigDialog(newValue: boolean) {
        this.__showConfigDialog.set(newValue);
    }
    private __configDialogText: ObservedPropertySimplePU<string>;
    get configDialogText() {
        return this.__configDialogText.get();
    }
    set configDialogText(newValue: string) {
        this.__configDialogText.set(newValue);
    }
    private __showConfigList: ObservedPropertySimplePU<boolean>;
    get showConfigList() {
        return this.__showConfigList.get();
    }
    set showConfigList(newValue: boolean) {
        this.__showConfigList.set(newValue);
    }
    private __pendingConfig: ObservedPropertyObjectPU<Record<string, number>>; // 待保存的配置
    get pendingConfig() {
        return this.__pendingConfig.get();
    }
    set pendingConfig(newValue: Record<string, number>) {
        this.__pendingConfig.set(newValue);
    }
    aboutToAppear() {
        console.log('MainApp aboutToAppear - loading configs');
        this.loadConfigs();
    }
    async loadConfigs() {
        console.log('Loading configs from storage...');
        const configStorage = await ConfigManager.getConfigs();
        console.log('Loaded config storage:', JSON.stringify(configStorage));
        this.configs = configStorage.configs;
        console.log('Configs loaded:', this.configs.length);
        if (configStorage.currentConfigId) {
            this.currentConfig = configStorage.configs.find(config => config.id === configStorage.currentConfigId) || null;
            if (this.currentConfig) {
                // 创建一个新的对象来确保@Watch能够检测到变化
                try {
                    this.stationConfig = JSON.parse(JSON.stringify(this.currentConfig.stations));
                }
                catch (error) {
                    console.error('Failed to parse station config:', error);
                    this.stationConfig = ConfigManager.getDefaultConfig();
                }
                console.log('Current config set:', this.currentConfig.name);
            }
        }
    }
    /**
     * @throws
     */
    async saveCurrentConfig(name: string) {
        if (name.trim() === '') {
            try {
                this.showToast('配置名称不能为空', 2000);
            }
            catch (error) {
                console.error('Failed to show toast:', error);
            }
            return;
        }
        // 使用待保存的配置数据
        const configToSave = Object.keys(this.pendingConfig).length > 0 ? this.pendingConfig : this.stationConfig;
        // 检查是否要更新现有配置还是创建新配置
        // 如果是从"设置站点"页面发起的保存请求（有pendingConfig），总是创建新配置
        // 如果是从监控页面的"保存配置"按钮发起的，更新当前配置
        const isNewConfig = Object.keys(this.pendingConfig).length > 0;
        if (isNewConfig) {
            // 创建新配置
            console.log('Creating new config:', name);
            await ConfigManager.addConfig(name, configToSave);
            await this.loadConfigs();
            try {
                this.showToast('配置已保存', 2000);
            }
            catch (error) {
                console.error('Failed to show toast:', error);
            }
        }
        else if (this.currentConfig) {
            // 更新现有配置
            console.log('Updating existing config:', this.currentConfig.name);
            await ConfigManager.updateConfig(this.currentConfig.id, name, configToSave);
            await this.loadConfigs();
            try {
                this.showToast('配置已更新', 2000);
            }
            catch (error) {
                console.error('Failed to show toast:', error);
            }
        }
        else {
            // 没有当前配置，也创建新配置
            console.log('Creating new config (no current config):', name);
            await ConfigManager.addConfig(name, configToSave);
            await this.loadConfigs();
            try {
                this.showToast('配置已保存', 2000);
            }
            catch (error) {
                console.error('Failed to show toast:', error);
            }
        }
        // 清空待保存配置
        this.pendingConfig = {};
        this.showConfigDialog = false;
        this.configDialogText = "";
    }
    async switchConfig(configId: string) {
        await ConfigManager.setCurrentConfig(configId);
        await this.loadConfigs();
    }
    async deleteConfig(configId: string) {
        await ConfigManager.deleteConfig(configId);
        await this.loadConfigs();
        try {
            this.showToast('配置已删除', 2000);
        }
        catch (error) {
            console.error('Failed to show toast:', error);
        }
    }
    // 处理保存配置请求
    handleSaveConfigRequest(newConfig: Record<string, number>) {
        this.pendingConfig = newConfig;
        this.configDialogText = this.currentConfig?.name || '';
        this.showConfigDialog = true;
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Index.ets(156:5)", "entry");
            Column.width('100%');
            Column.height('100%');
            Column.backgroundColor('#000000');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // 配置选择器
            if (this.configs.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Row.create();
                        Row.debugLine("entry/src/main/ets/pages/Index.ets(159:9)", "entry");
                        Row.width('90%');
                        Row.padding(10);
                        Row.backgroundColor('#1a1a1c');
                        Row.borderRadius(8);
                        Row.margin({ top: 10 });
                    }, Row);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create("当前配置:");
                        Text.debugLine("entry/src/main/ets/pages/Index.ets(160:11)", "entry");
                        Text.fontColor(Color.White);
                        Text.fontSize(14);
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel(this.currentConfig?.name || '请选择配置');
                        Button.debugLine("entry/src/main/ets/pages/Index.ets(162:11)", "entry");
                        Button.onClick(() => { this.showConfigList = !this.showConfigList; });
                        Button.layoutWeight(1);
                        Button.margin({ left: 10 });
                    }, Button);
                    Button.pop();
                    Row.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        If.create();
                        // 配置列表
                        if (this.showConfigList) {
                            this.ifElseBranchUpdateFunction(0, () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create();
                                    Column.debugLine("entry/src/main/ets/pages/Index.ets(177:11)", "entry");
                                    Column.width('90%');
                                    Column.padding(10);
                                    Column.backgroundColor('#1a1a1c');
                                    Column.borderRadius(8);
                                    Column.margin({ top: 5 });
                                }, Column);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    ForEach.create();
                                    const forEachItemGenFunction = _item => {
                                        const config = _item;
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Row.create();
                                            Row.debugLine("entry/src/main/ets/pages/Index.ets(179:15)", "entry");
                                            Row.width('100%');
                                            Row.padding(8);
                                            Row.backgroundColor('#2c2c2e');
                                            Row.borderRadius(6);
                                            Row.margin({ bottom: 5 });
                                        }, Row);
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Text.create(config.name);
                                            Text.debugLine("entry/src/main/ets/pages/Index.ets(180:17)", "entry");
                                            Text.fontColor(Color.White);
                                            Text.fontSize(14);
                                        }, Text);
                                        Text.pop();
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Blank.create();
                                            Blank.debugLine("entry/src/main/ets/pages/Index.ets(181:17)", "entry");
                                        }, Blank);
                                        Blank.pop();
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            If.create();
                                            if (this.currentConfig?.id === config.id) {
                                                this.ifElseBranchUpdateFunction(0, () => {
                                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                        Text.create("当前");
                                                        Text.debugLine("entry/src/main/ets/pages/Index.ets(183:19)", "entry");
                                                        Text.fontColor('#30d158');
                                                        Text.fontSize(12);
                                                    }, Text);
                                                    Text.pop();
                                                });
                                            }
                                            else {
                                                this.ifElseBranchUpdateFunction(1, () => {
                                                });
                                            }
                                        }, If);
                                        If.pop();
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Button.createWithLabel("选择");
                                            Button.debugLine("entry/src/main/ets/pages/Index.ets(185:17)", "entry");
                                            Button.onClick(async () => {
                                                try {
                                                    await this.switchConfig(config.id);
                                                }
                                                catch (error) {
                                                    console.error('Failed to switch config:', error);
                                                    try {
                                                        this.showToast('切换配置失败', 2000);
                                                    }
                                                    catch (toastError) {
                                                        console.error('Failed to show error toast:', toastError);
                                                    }
                                                }
                                                this.showConfigList = false;
                                            });
                                            Button.fontSize(10);
                                            Button.margin({ left: 10 });
                                        }, Button);
                                        Button.pop();
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Button.createWithLabel("删除");
                                            Button.debugLine("entry/src/main/ets/pages/Index.ets(201:17)", "entry");
                                            Button.onClick(async () => {
                                                try {
                                                    await this.deleteConfig(config.id);
                                                }
                                                catch (error) {
                                                    console.error('Failed to delete config:', error);
                                                    try {
                                                        this.showToast('删除配置失败', 2000);
                                                    }
                                                    catch (toastError) {
                                                        console.error('Failed to show error toast:', toastError);
                                                    }
                                                }
                                            });
                                            Button.fontSize(10);
                                            Button.backgroundColor('#ff453a');
                                            Button.margin({ left: 5 });
                                        }, Button);
                                        Button.pop();
                                        Row.pop();
                                    };
                                    this.forEachUpdateFunction(elmtId, this.configs, forEachItemGenFunction);
                                }, ForEach);
                                ForEach.pop();
                                Column.pop();
                            });
                        }
                        else {
                            this.ifElseBranchUpdateFunction(1, () => {
                            });
                        }
                    }, If);
                    If.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Tabs.create({ barPosition: BarPosition.End });
            Tabs.debugLine("entry/src/main/ets/pages/Index.ets(233:7)", "entry");
            Tabs.layoutWeight(1);
        }, Tabs);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TabContent.create(() => {
                {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        if (isInitialRender) {
                            let componentCall = new ChargerMonitorUI(this, {
                                stationConfig: this.__stationConfig,
                                configs: this.__configs,
                                currentConfig: this.__currentConfig
                            }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 235, col: 11 });
                            ViewPU.create(componentCall);
                            let paramsLambda = () => {
                                return {
                                    stationConfig: this.stationConfig,
                                    configs: this.configs,
                                    currentConfig: this.currentConfig
                                };
                            };
                            componentCall.paramsGenerator_ = paramsLambda;
                        }
                        else {
                            this.updateStateVarsOfChildByElmtId(elmtId, {});
                        }
                    }, { name: "ChargerMonitorUI" });
                }
            });
            TabContent.tabBar("监控");
            TabContent.debugLine("entry/src/main/ets/pages/Index.ets(234:9)", "entry");
        }, TabContent);
        TabContent.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TabContent.create(() => {
                {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        if (isInitialRender) {
                            let componentCall = new StationPickerUI(this, {
                                stationConfig: this.__stationConfig,
                                onSaveConfig: (newConfig: Record<string, number>) => {
                                    this.handleSaveConfigRequest(newConfig);
                                }
                            }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 243, col: 11 });
                            ViewPU.create(componentCall);
                            let paramsLambda = () => {
                                return {
                                    stationConfig: this.stationConfig,
                                    onSaveConfig: (newConfig: Record<string, number>) => {
                                        this.handleSaveConfigRequest(newConfig);
                                    }
                                };
                            };
                            componentCall.paramsGenerator_ = paramsLambda;
                        }
                        else {
                            this.updateStateVarsOfChildByElmtId(elmtId, {});
                        }
                    }, { name: "StationPickerUI" });
                }
            });
            TabContent.tabBar("设置站点");
            TabContent.debugLine("entry/src/main/ets/pages/Index.ets(242:9)", "entry");
        }, TabContent);
        TabContent.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TabContent.create(() => {
                {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        if (isInitialRender) {
                            let componentCall = new MapViewerUI(this, {}, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 252, col: 11 });
                            ViewPU.create(componentCall);
                            let paramsLambda = () => {
                                return {};
                            };
                            componentCall.paramsGenerator_ = paramsLambda;
                        }
                        else {
                            this.updateStateVarsOfChildByElmtId(elmtId, {});
                        }
                    }, { name: "MapViewerUI" });
                }
            });
            TabContent.tabBar("地图");
            TabContent.debugLine("entry/src/main/ets/pages/Index.ets(251:9)", "entry");
        }, TabContent);
        TabContent.pop();
        Tabs.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // 配置命名对话框
            if (this.showConfigDialog) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.debugLine("entry/src/main/ets/pages/Index.ets(259:9)", "entry");
                        Column.width(300);
                        Column.padding(20);
                        Column.backgroundColor('#1c1c1e');
                        Column.borderRadius(12);
                        Column.alignItems(HorizontalAlign.Center);
                        Column.position({ x: '50%', y: '40%' });
                        Column.translate({ x: -150, y: -100 });
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create("配置名称");
                        Text.debugLine("entry/src/main/ets/pages/Index.ets(260:11)", "entry");
                        Text.fontColor(Color.White);
                        Text.fontSize(16);
                        Text.fontWeight(FontWeight.Bold);
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        TextInput.create({ placeholder: '输入配置名称', text: this.configDialogText });
                        TextInput.debugLine("entry/src/main/ets/pages/Index.ets(261:11)", "entry");
                        TextInput.onChange((value) => { this.configDialogText = value; });
                        TextInput.width('100%');
                        TextInput.height(40);
                        TextInput.backgroundColor('#2c2c2e');
                        TextInput.fontColor(Color.White);
                        TextInput.margin({ top: 10, bottom: 10 });
                    }, TextInput);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Row.create();
                        Row.debugLine("entry/src/main/ets/pages/Index.ets(269:11)", "entry");
                        Row.width('100%');
                    }, Row);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel("取消");
                        Button.debugLine("entry/src/main/ets/pages/Index.ets(270:13)", "entry");
                        Button.onClick(() => {
                            this.showConfigDialog = false;
                            this.configDialogText = "";
                            this.pendingConfig = {};
                        });
                        Button.backgroundColor('#48484a');
                        Button.layoutWeight(1);
                        Button.margin({ right: 10 });
                    }, Button);
                    Button.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel("保存");
                        Button.debugLine("entry/src/main/ets/pages/Index.ets(280:13)", "entry");
                        Button.onClick(async () => {
                            try {
                                await this.saveCurrentConfig(this.configDialogText);
                            }
                            catch (error) {
                                console.error('Failed to save config:', error);
                                try {
                                    this.showToast('保存配置失败', 2000);
                                }
                                catch (toastError) {
                                    console.error('Failed to show error toast:', toastError);
                                }
                            }
                        });
                        Button.backgroundColor('#0a84ff');
                        Button.layoutWeight(1);
                    }, Button);
                    Button.pop();
                    Row.pop();
                    Column.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "MainApp";
    }
}
class ChargerMonitorUI extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__stationConfig = new SynchedPropertyObjectTwoWayPU(params.stationConfig, this, "stationConfig");
        this.__configs = new SynchedPropertyObjectTwoWayPU(params.configs, this, "configs");
        this.__currentConfig = new SynchedPropertyObjectTwoWayPU(params.currentConfig, this, "currentConfig");
        this.__isExpanded = new ObservedPropertySimplePU(false, this, "isExpanded");
        this.__stations = new ObservedPropertyObjectPU([], this, "stations");
        this.__searchText = new ObservedPropertySimplePU("", this, "searchText");
        this.__sortMode = new ObservedPropertySimplePU(SORT_MODE.FREE_COUNT, this, "sortMode");
        this.__showSortMenu = new ObservedPropertySimplePU(false, this, "showSortMenu");
        this.__isLoading = new ObservedPropertySimplePU(true, this, "isLoading");
        this.__showConfigList = new ObservedPropertySimplePU(false, this, "showConfigList");
        this.__canRefresh = new ObservedPropertySimplePU(true, this, "canRefresh");
        this.__refreshCooldown = new ObservedPropertySimplePU(0, this, "refreshCooldown");
        this.__screenHeight = new ObservedPropertySimplePU(800, this, "screenHeight");
        this.refreshInterval = -1;
        this.lastConfigHash = "";
        this.cooldownInterval = -1;
        this.setInitiallyProvidedValue(params);
        this.declareWatch("stationConfig", this.onStationConfigChange);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: ChargerMonitorUI_Params) {
        if (params.isExpanded !== undefined) {
            this.isExpanded = params.isExpanded;
        }
        if (params.stations !== undefined) {
            this.stations = params.stations;
        }
        if (params.searchText !== undefined) {
            this.searchText = params.searchText;
        }
        if (params.sortMode !== undefined) {
            this.sortMode = params.sortMode;
        }
        if (params.showSortMenu !== undefined) {
            this.showSortMenu = params.showSortMenu;
        }
        if (params.isLoading !== undefined) {
            this.isLoading = params.isLoading;
        }
        if (params.showConfigList !== undefined) {
            this.showConfigList = params.showConfigList;
        }
        if (params.canRefresh !== undefined) {
            this.canRefresh = params.canRefresh;
        }
        if (params.refreshCooldown !== undefined) {
            this.refreshCooldown = params.refreshCooldown;
        }
        if (params.screenHeight !== undefined) {
            this.screenHeight = params.screenHeight;
        }
        if (params.refreshInterval !== undefined) {
            this.refreshInterval = params.refreshInterval;
        }
        if (params.lastConfigHash !== undefined) {
            this.lastConfigHash = params.lastConfigHash;
        }
        if (params.cooldownInterval !== undefined) {
            this.cooldownInterval = params.cooldownInterval;
        }
    }
    updateStateVars(params: ChargerMonitorUI_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__stationConfig.purgeDependencyOnElmtId(rmElmtId);
        this.__configs.purgeDependencyOnElmtId(rmElmtId);
        this.__currentConfig.purgeDependencyOnElmtId(rmElmtId);
        this.__isExpanded.purgeDependencyOnElmtId(rmElmtId);
        this.__stations.purgeDependencyOnElmtId(rmElmtId);
        this.__searchText.purgeDependencyOnElmtId(rmElmtId);
        this.__sortMode.purgeDependencyOnElmtId(rmElmtId);
        this.__showSortMenu.purgeDependencyOnElmtId(rmElmtId);
        this.__isLoading.purgeDependencyOnElmtId(rmElmtId);
        this.__showConfigList.purgeDependencyOnElmtId(rmElmtId);
        this.__canRefresh.purgeDependencyOnElmtId(rmElmtId);
        this.__refreshCooldown.purgeDependencyOnElmtId(rmElmtId);
        this.__screenHeight.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__stationConfig.aboutToBeDeleted();
        this.__configs.aboutToBeDeleted();
        this.__currentConfig.aboutToBeDeleted();
        this.__isExpanded.aboutToBeDeleted();
        this.__stations.aboutToBeDeleted();
        this.__searchText.aboutToBeDeleted();
        this.__sortMode.aboutToBeDeleted();
        this.__showSortMenu.aboutToBeDeleted();
        this.__isLoading.aboutToBeDeleted();
        this.__showConfigList.aboutToBeDeleted();
        this.__canRefresh.aboutToBeDeleted();
        this.__refreshCooldown.aboutToBeDeleted();
        this.__screenHeight.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    // 辅助方法：显示Toast消息（API 18+兼容）
    private showToast(message: string, duration: number = 2000): void {
        try {
            this.getUIContext().getPromptAction().openToast({
                message: message,
                duration: duration
            });
        }
        catch (error) {
            console.error('Failed to show toast:', error);
        }
    }
    private __stationConfig: SynchedPropertySimpleOneWayPU<Record<string, number>>;
    get stationConfig() {
        return this.__stationConfig.get();
    }
    set stationConfig(newValue: Record<string, number>) {
        this.__stationConfig.set(newValue);
    }
    private __configs: SynchedPropertySimpleOneWayPU<ChargerConfig[]>;
    get configs() {
        return this.__configs.get();
    }
    set configs(newValue: ChargerConfig[]) {
        this.__configs.set(newValue);
    }
    private __currentConfig: SynchedPropertySimpleOneWayPU<ChargerConfig | null>;
    get currentConfig() {
        return this.__currentConfig.get();
    }
    set currentConfig(newValue: ChargerConfig | null) {
        this.__currentConfig.set(newValue);
    }
    private __isExpanded: ObservedPropertySimplePU<boolean>;
    get isExpanded() {
        return this.__isExpanded.get();
    }
    set isExpanded(newValue: boolean) {
        this.__isExpanded.set(newValue);
    }
    private __stations: ObservedPropertyObjectPU<StationData[]>;
    get stations() {
        return this.__stations.get();
    }
    set stations(newValue: StationData[]) {
        this.__stations.set(newValue);
    }
    private __searchText: ObservedPropertySimplePU<string>;
    get searchText() {
        return this.__searchText.get();
    }
    set searchText(newValue: string) {
        this.__searchText.set(newValue);
    }
    private __sortMode: ObservedPropertySimplePU<number>;
    get sortMode() {
        return this.__sortMode.get();
    }
    set sortMode(newValue: number) {
        this.__sortMode.set(newValue);
    }
    private __showSortMenu: ObservedPropertySimplePU<boolean>;
    get showSortMenu() {
        return this.__showSortMenu.get();
    }
    set showSortMenu(newValue: boolean) {
        this.__showSortMenu.set(newValue);
    }
    private __isLoading: ObservedPropertySimplePU<boolean>;
    get isLoading() {
        return this.__isLoading.get();
    }
    set isLoading(newValue: boolean) {
        this.__isLoading.set(newValue);
    }
    private __showConfigList: ObservedPropertySimplePU<boolean>;
    get showConfigList() {
        return this.__showConfigList.get();
    }
    set showConfigList(newValue: boolean) {
        this.__showConfigList.set(newValue);
    }
    private __canRefresh: ObservedPropertySimplePU<boolean>; // 是否可以刷新
    get canRefresh() {
        return this.__canRefresh.get();
    }
    set canRefresh(newValue: boolean) {
        this.__canRefresh.set(newValue);
    }
    private __refreshCooldown: ObservedPropertySimplePU<number>; // 刷新冷却时间
    get refreshCooldown() {
        return this.__refreshCooldown.get();
    }
    set refreshCooldown(newValue: number) {
        this.__refreshCooldown.set(newValue);
    }
    private __screenHeight: ObservedPropertySimplePU<number>; // 默认屏幕高度
    get screenHeight() {
        return this.__screenHeight.get();
    }
    set screenHeight(newValue: number) {
        this.__screenHeight.set(newValue);
    }
    private refreshInterval: number;
    private lastConfigHash: string; // 用于检测配置变化
    private cooldownInterval: number; // 冷却计时器
    aboutToAppear() {
        // 获取屏幕高度
        this.getScreenHeight();
        this.fetchData();
        // 定时刷新数据（30秒）
        this.refreshInterval = setInterval(() => {
            this.fetchData();
        }, 30000);
    }
    // 获取屏幕高度
    getScreenHeight() {
        try {
            const defaultDisplay = display.getDefaultDisplaySync();
            this.screenHeight = defaultDisplay.height;
            console.log('Screen height detected:', this.screenHeight);
        }
        catch (error) {
            console.error('Failed to get screen height, using default:', error);
            this.screenHeight = 800; // 默认高度
        }
    }
    // 计算自适应展开高度
    getExpandedHeight(): number {
        // 计算可用高度：屏幕高度 - 顶部间距 - 底部安全区域
        const topMargin = 20; // 顶部间距
        const bottomSafeArea = 60; // 底部安全区域（包含底部导航栏）
        const maxHeight = this.screenHeight - topMargin - bottomSafeArea;
        // 限制最小和最大高度
        const minHeight = 300; // 最小展开高度
        const calculatedHeight = Math.max(minHeight, Math.min(maxHeight, 600)); // 最大不超过600
        console.log('Calculated expanded height:', calculatedHeight);
        return calculatedHeight;
    }
    aboutToDisappear() {
        // 清理所有定时器
        if (this.refreshInterval !== -1) {
            clearInterval(this.refreshInterval);
            this.refreshInterval = -1;
        }
        if (this.cooldownInterval !== -1) {
            clearInterval(this.cooldownInterval);
            this.cooldownInterval = -1;
        }
        console.log('ChargerMonitorUI: All timers cleaned up');
    }
    // 监听stationConfig变化 - 防抖响应
    onStationConfigChange() {
        console.log('Config changed detected by @Watch, scheduling data refresh...');
        // 使用防抖机制，避免频繁刷新
        setTimeout(() => {
            this.fetchData();
        }, 300); // 300ms防抖延迟
    }
    // 手动刷新数据
    async manualRefresh() {
        if (!this.canRefresh) {
            const remainingTime = Math.ceil(this.refreshCooldown / 1000);
            try {
                this.showToast(`刷新过快，请等待${remainingTime}秒后重试`, 2000);
            }
            catch (error) {
                console.error('Failed to show toast:', error);
            }
            return;
        }
        console.log('Manual refresh triggered');
        // 设置冷却时间（3秒）
        this.canRefresh = false;
        this.refreshCooldown = 3000;
        // 立即刷新数据
        await this.fetchData();
        // 启动冷却计时器
        if (this.cooldownInterval !== -1) {
            clearInterval(this.cooldownInterval);
        }
        this.cooldownInterval = setInterval(() => {
            this.refreshCooldown -= 100;
            if (this.refreshCooldown <= 0) {
                this.canRefresh = true;
                this.refreshCooldown = 0;
                if (this.cooldownInterval !== -1) {
                    clearInterval(this.cooldownInterval);
                    this.cooldownInterval = -1;
                }
            }
        }, 100);
    }
    async fetchData() {
        // 更新配置哈希
        this.lastConfigHash = JSON.stringify(this.stationConfig);
        let newStations: StationData[] = [];
        let keys = Object.keys(this.stationConfig);
        // 使用Promise.all并行获取数据，提高效率
        const stationPromises = keys.map(async (name) => {
            const id = this.stationConfig[name];
            try {
                const data = await ChargerApi.fetchStation(id, name);
                // 验证数据有效性
                if (data && data.outlets && data.outlets.length > 0) {
                    return data;
                }
            }
            catch (error) {
                console.error(`Failed to fetch station ${name}:`, error);
            }
            return null;
        });
        const results = await Promise.allSettled(stationPromises);
        results.forEach(result => {
            if (result.status === 'fulfilled' && result.value) {
                newStations.push(result.value);
            }
        });
        this.stations = newStations;
        this.isLoading = false;
        console.log(`Data fetch completed: ${newStations.length} stations loaded`);
    }
    getStats(): StatsResult {
        let total = 0;
        let free = 0;
        this.stations.forEach(s => {
            total += s.outlets.length;
            free += s.outlets.filter(o => o.status === 1).length;
        });
        return { total, free, anyFree: free > 0 };
    }
    private getFreeCount(outlets: OutletDetail[]): number {
        let count = 0;
        for (let i = 0; i < outlets.length; i++) {
            if (outlets[i].status === 1)
                count++;
        }
        return count;
    }
    getFilteredStations(): StationWithFreeCount[] {
        let result: StationWithFreeCount[] = [];
        for (let i = 0; i < this.stations.length; i++) {
            let s = this.stations[i];
            if (s.name.toLowerCase().includes(this.searchText.toLowerCase())) {
                let sortedOutlets = s.outlets.slice();
                for (let j = 0; j < sortedOutlets.length - 1; j++) {
                    for (let k = j + 1; k < sortedOutlets.length; k++) {
                        let a = sortedOutlets[j];
                        let b = sortedOutlets[k];
                        let shouldSwap = false;
                        if (this.sortMode === SORT_MODE.POWER)
                            shouldSwap = (b.power_w || 0) > (a.power_w || 0);
                        else if (this.sortMode === SORT_MODE.FEE)
                            shouldSwap = (b.fee || 0) > (a.fee || 0);
                        else if (this.sortMode === SORT_MODE.DURATION)
                            shouldSwap = (b.used_min || 0) > (a.used_min || 0);
                        else
                            shouldSwap = a.serial > b.serial;
                        if (shouldSwap) {
                            let temp = sortedOutlets[j];
                            sortedOutlets[j] = sortedOutlets[k];
                            sortedOutlets[k] = temp;
                        }
                    }
                }
                let station: StationData = { name: s.name, id: s.id, outlets: sortedOutlets };
                result.push({ station, freeCount: this.getFreeCount(sortedOutlets) } as StationWithFreeCount);
            }
        }
        // 按照选择的排序模式进行排序
        if (this.sortMode === SORT_MODE.FREE_COUNT) {
            // 按照空闲插座数量降序排序（数量多的排在上面）
            result.sort((a, b) => b.freeCount - a.freeCount);
        }
        else {
            // 其他排序模式保持原有逻辑
            result.sort((a, b) => {
                if (this.sortMode === SORT_MODE.POWER) {
                    return this.getMaxPower(b.station.outlets) - this.getMaxPower(a.station.outlets);
                }
                else if (this.sortMode === SORT_MODE.FEE) {
                    return this.getMaxFee(b.station.outlets) - this.getMaxFee(a.station.outlets);
                }
                else if (this.sortMode === SORT_MODE.DURATION) {
                    return this.getMaxDuration(b.station.outlets) - this.getMaxDuration(a.station.outlets);
                }
                else {
                    // 默认按站点名称排序
                    return a.station.name.localeCompare(b.station.name);
                }
            });
        }
        return result;
    }
    // 获取站点插座最大功率
    private getMaxPower(outlets: OutletDetail[]): number {
        let maxPower = 0;
        for (let i = 0; i < outlets.length; i++) {
            const power = outlets[i].power_w || 0;
            if (power > maxPower) {
                maxPower = power;
            }
        }
        return maxPower;
    }
    // 获取站点插座最大费用
    private getMaxFee(outlets: OutletDetail[]): number {
        let maxFee = 0;
        for (let i = 0; i < outlets.length; i++) {
            const fee = outlets[i].fee || 0;
            if (fee > maxFee) {
                maxFee = fee;
            }
        }
        return maxFee;
    }
    // 获取站点插座最大使用时长
    private getMaxDuration(outlets: OutletDetail[]): number {
        let maxDuration = 0;
        for (let i = 0; i < outlets.length; i++) {
            const duration = outlets[i].used_min || 0;
            if (duration > maxDuration) {
                maxDuration = duration;
            }
        }
        return maxDuration;
    }
    // 根据排序模式值获取显示文本
    private getSortModeText(mode: number): string {
        switch (mode) {
            case SORT_MODE.FREE_COUNT:
                return '空闲插座数量';
            case SORT_MODE.SERIAL:
                return '插座编号';
            case SORT_MODE.POWER:
                return '功率';
            case SORT_MODE.FEE:
                return '费用';
            case SORT_MODE.DURATION:
                return '使用时长';
            default:
                return '空闲插座数量';
        }
    }
    // 构建排序菜单项
    buildSortMenuItem(text: string, mode: number, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(text);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(608:5)", "entry");
            Text.fontSize(10);
            Text.fontColor(this.sortMode === mode ? '#0a84ff' : Color.White);
            Text.backgroundColor(this.sortMode === mode ? '#1c1c1e' : 'transparent');
            Text.width('100%');
            Text.height(24);
            Text.textAlign(TextAlign.Start);
            Text.padding({ left: 10 });
            Text.onClick(() => {
                this.sortMode = mode;
                this.showSortMenu = false;
            });
        }, Text);
        Text.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Index.ets(623:5)", "entry");
            Column.width('100%');
            Column.height('100%');
            Column.backgroundColor('#000000');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Index.ets(626:7)", "entry");
            Column.width('100%');
            Column.backgroundColor('#000000');
            Column.borderRadius(12);
            Column.margin({ top: 10 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 头部胶囊
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(628:9)", "entry");
            // 头部胶囊
            Row.width('100%');
            // 头部胶囊
            Row.height(46);
            // 头部胶囊
            Row.padding({ left: 20, right: 20 });
            // 头部胶囊
            Row.onClick(() => { this.isExpanded = !this.isExpanded; });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.isLoading) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create("正在获取数据…");
                        Text.debugLine("entry/src/main/ets/pages/Index.ets(630:13)", "entry");
                        Text.fontColor('#b4b4b4');
                        Text.fontSize(14);
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Circle.create({ width: 12, height: 12 });
                        Circle.debugLine("entry/src/main/ets/pages/Index.ets(632:13)", "entry");
                        Circle.fill(this.getStats().anyFree ? '#30d158' : '#ff453a');
                        Circle.margin({ right: 10 });
                    }, Circle);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.getStats().anyFree ? "有空闲插座" : "全部占用");
                        Text.debugLine("entry/src/main/ets/pages/Index.ets(633:13)", "entry");
                        Text.fontColor(Color.White);
                        Text.fontSize(16);
                        Text.fontWeight(FontWeight.Medium);
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Blank.create();
                        Blank.debugLine("entry/src/main/ets/pages/Index.ets(634:13)", "entry");
                    }, Blank);
                    Blank.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(`${this.getStats().free}/${this.getStats().total}`);
                        Text.debugLine("entry/src/main/ets/pages/Index.ets(635:13)", "entry");
                        Text.fontColor(this.getStats().anyFree ? '#30d158' : '#ff453a');
                        Text.fontSize(16);
                        Text.fontWeight(FontWeight.Bold);
                    }, Text);
                    Text.pop();
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 刷新按钮
            Button.createWithLabel(this.canRefresh ? "刷新" : `冷却中(${Math.ceil(this.refreshCooldown / 1000)}s)`);
            Button.debugLine("entry/src/main/ets/pages/Index.ets(639:11)", "entry");
            // 刷新按钮
            Button.onClick(async () => {
                try {
                    await this.manualRefresh();
                }
                catch (error) {
                    console.error('Manual refresh failed:', error);
                    try {
                        this.showToast('刷新失败', 2000);
                    }
                    catch (toastError) {
                        console.error('Failed to show error toast:', toastError);
                    }
                }
            });
            // 刷新按钮
            Button.enabled(this.canRefresh);
            // 刷新按钮
            Button.fontSize(12);
            // 刷新按钮
            Button.backgroundColor(this.canRefresh ? '#0a84ff' : '#48484a');
            // 刷新按钮
            Button.fontColor(Color.White);
            // 刷新按钮
            Button.width(60);
            // 刷新按钮
            Button.height(28);
            // 刷新按钮
            Button.margin({ left: 10 });
        }, Button);
        // 刷新按钮
        Button.pop();
        // 头部胶囊
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // 展开面板
            if (this.isExpanded) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.debugLine("entry/src/main/ets/pages/Index.ets(667:11)", "entry");
                        Column.width('100%');
                        Column.backgroundColor('#000000');
                        Column.padding({ left: 10, right: 10 });
                        Column.height(this.getExpandedHeight());
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        TextInput.create({ placeholder: '搜索站点名称…', text: this.searchText });
                        TextInput.debugLine("entry/src/main/ets/pages/Index.ets(668:13)", "entry");
                        TextInput.onChange((value) => { this.searchText = value; });
                        TextInput.height(36);
                        TextInput.backgroundColor('rgba(0,0,0,0.5)');
                        TextInput.fontColor(Color.White);
                        TextInput.margin({ top: 10, bottom: 10 });
                    }, TextInput);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        // 排序模式选择器 - 使用简化按钮组（节省空间）
                        Row.create();
                        Row.debugLine("entry/src/main/ets/pages/Index.ets(676:13)", "entry");
                        // 排序模式选择器 - 使用简化按钮组（节省空间）
                        Row.width('100%');
                        // 排序模式选择器 - 使用简化按钮组（节省空间）
                        Row.justifyContent(FlexAlign.Start);
                        // 排序模式选择器 - 使用简化按钮组（节省空间）
                        Row.margin({ bottom: 10 });
                    }, Row);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create("排序:");
                        Text.debugLine("entry/src/main/ets/pages/Index.ets(677:15)", "entry");
                        Text.fontColor('#8e8e93');
                        Text.fontSize(12);
                        Text.margin({ right: 10 });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel(this.getSortModeText(this.sortMode));
                        Button.debugLine("entry/src/main/ets/pages/Index.ets(678:15)", "entry");
                        Button.onClick(() => {
                            this.showSortMenu = !this.showSortMenu;
                        });
                        Button.fontSize(10);
                        Button.backgroundColor('#48484a');
                        Button.fontColor(Color.White);
                        Button.width(80);
                        Button.height(24);
                        Button.borderRadius(4);
                    }, Button);
                    Button.pop();
                    // 排序模式选择器 - 使用简化按钮组（节省空间）
                    Row.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        If.create();
                        // 排序菜单
                        if (this.showSortMenu) {
                            this.ifElseBranchUpdateFunction(0, () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create();
                                    Column.debugLine("entry/src/main/ets/pages/Index.ets(695:15)", "entry");
                                    Column.backgroundColor('#2c2c2e');
                                    Column.borderRadius(4);
                                    Column.width(100);
                                    Column.margin({ bottom: 10 });
                                }, Column);
                                this.buildSortMenuItem.bind(this)('空闲插座数量', SORT_MODE.FREE_COUNT);
                                this.buildSortMenuItem.bind(this)('插座编号', SORT_MODE.SERIAL);
                                this.buildSortMenuItem.bind(this)('功率', SORT_MODE.POWER);
                                this.buildSortMenuItem.bind(this)('费用', SORT_MODE.FEE);
                                this.buildSortMenuItem.bind(this)('使用时长', SORT_MODE.DURATION);
                                Column.pop();
                            });
                        }
                        else {
                            this.ifElseBranchUpdateFunction(1, () => {
                            });
                        }
                    }, If);
                    If.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        List.create({ space: 10 });
                        List.debugLine("entry/src/main/ets/pages/Index.ets(708:13)", "entry");
                        List.height(this.getExpandedHeight() - 160);
                        List.backgroundColor('#000000');
                        List.padding({ left: 10, right: 10 });
                    }, List);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = (_item, index: number) => {
                            const item = _item;
                            {
                                const itemCreation = (elmtId, isInitialRender) => {
                                    ViewStackProcessor.StartGetAccessRecordingFor(elmtId);
                                    ListItem.create(deepRenderFunction, true);
                                    if (!isInitialRender) {
                                        ListItem.pop();
                                    }
                                    ViewStackProcessor.StopGetAccessRecording();
                                };
                                const itemCreation2 = (elmtId, isInitialRender) => {
                                    ListItem.create(deepRenderFunction, true);
                                    ListItem.debugLine("entry/src/main/ets/pages/Index.ets(710:17)", "entry");
                                };
                                const deepRenderFunction = (elmtId, isInitialRender) => {
                                    itemCreation(elmtId, isInitialRender);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Column.create();
                                        Column.debugLine("entry/src/main/ets/pages/Index.ets(711:19)", "entry");
                                        Column.backgroundColor('#1c1c1e');
                                        Column.borderRadius(8);
                                        Column.padding(0);
                                    }, Column);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Row.create();
                                        Row.debugLine("entry/src/main/ets/pages/Index.ets(712:21)", "entry");
                                        Row.width('100%');
                                        Row.padding(12);
                                        Row.border({ width: { bottom: 1 }, color: 'rgba(255,255,255,0.05)' });
                                    }, Row);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(item.station.name);
                                        Text.debugLine("entry/src/main/ets/pages/Index.ets(713:23)", "entry");
                                        Text.fontColor(Color.White);
                                        Text.fontSize(14);
                                        Text.fontWeight(FontWeight.Bold);
                                    }, Text);
                                    Text.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Blank.create();
                                        Blank.debugLine("entry/src/main/ets/pages/Index.ets(714:23)", "entry");
                                    }, Blank);
                                    Blank.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(` ${item.freeCount}/${item.station.outlets.length} `);
                                        Text.debugLine("entry/src/main/ets/pages/Index.ets(715:23)", "entry");
                                        Text.fontColor(item.freeCount > 0 ? '#30d158' : '#ff453a');
                                        Text.backgroundColor(item.freeCount > 0 ? 'rgba(48,209,88,0.15)' : 'rgba(255,69,58,0.15)');
                                        Text.borderRadius(10);
                                        Text.fontSize(12);
                                        Text.padding(4);
                                    }, Text);
                                    Text.pop();
                                    Row.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Column.create({ space: 6 });
                                        Column.debugLine("entry/src/main/ets/pages/Index.ets(722:21)", "entry");
                                    }, Column);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        ForEach.create();
                                        const forEachItemGenFunction = _item => {
                                            const outlet = _item;
                                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                Row.create();
                                                Row.debugLine("entry/src/main/ets/pages/Index.ets(724:25)", "entry");
                                                Row.width('100%');
                                                Row.padding({ left: 12, right: 12, top: 6, bottom: 6 });
                                            }, Row);
                                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                Rect.create({ width: 3, height: 20 });
                                                Rect.debugLine("entry/src/main/ets/pages/Index.ets(725:27)", "entry");
                                                Rect.fill(outlet.status === 1 ? '#30d158' : (outlet.status === 2 ? '#ff453a' : '#ffd60a'));
                                                Rect.radius(1.5);
                                                Rect.margin({ right: 10 });
                                            }, Rect);
                                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                Text.create(`插座${outlet.serial}`);
                                                Text.debugLine("entry/src/main/ets/pages/Index.ets(726:27)", "entry");
                                                Text.fontColor(Color.White);
                                                Text.fontSize(13);
                                            }, Text);
                                            Text.pop();
                                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                Blank.create();
                                                Blank.debugLine("entry/src/main/ets/pages/Index.ets(727:27)", "entry");
                                            }, Blank);
                                            Blank.pop();
                                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                If.create();
                                                if (outlet.status === 2) {
                                                    this.ifElseBranchUpdateFunction(0, () => {
                                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                            If.create();
                                                            if (outlet.power_w !== undefined) {
                                                                this.ifElseBranchUpdateFunction(0, () => {
                                                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                                        Text.create(`${outlet.power_w}W`);
                                                                        Text.debugLine("entry/src/main/ets/pages/Index.ets(729:63)", "entry");
                                                                        __Text__chipStyle('#0a84ff');
                                                                    }, Text);
                                                                    Text.pop();
                                                                });
                                                            }
                                                            else {
                                                                this.ifElseBranchUpdateFunction(1, () => {
                                                                });
                                                            }
                                                        }, If);
                                                        If.pop();
                                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                            If.create();
                                                            if (outlet.fee !== undefined) {
                                                                this.ifElseBranchUpdateFunction(0, () => {
                                                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                                        Text.create(`¥${outlet.fee.toFixed(2)}`);
                                                                        Text.debugLine("entry/src/main/ets/pages/Index.ets(730:59)", "entry");
                                                                        __Text__chipStyle('#30d158');
                                                                    }, Text);
                                                                    Text.pop();
                                                                });
                                                            }
                                                            else {
                                                                this.ifElseBranchUpdateFunction(1, () => {
                                                                });
                                                            }
                                                        }, If);
                                                        If.pop();
                                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                            If.create();
                                                            if (outlet.used_min !== undefined) {
                                                                this.ifElseBranchUpdateFunction(0, () => {
                                                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                                        Text.create(`${outlet.used_min}分钟`);
                                                                        Text.debugLine("entry/src/main/ets/pages/Index.ets(731:64)", "entry");
                                                                        __Text__chipStyle('#ffd60a');
                                                                    }, Text);
                                                                    Text.pop();
                                                                });
                                                            }
                                                            else {
                                                                this.ifElseBranchUpdateFunction(1, () => {
                                                                });
                                                            }
                                                        }, If);
                                                        If.pop();
                                                    });
                                                }
                                                else {
                                                    this.ifElseBranchUpdateFunction(1, () => {
                                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                            Text.create(outlet.status === 1 ? '空闲' : '故障');
                                                            Text.debugLine("entry/src/main/ets/pages/Index.ets(733:29)", "entry");
                                                            __Text__chipStyle(outlet.status === 1 ? '#30d158' : '#ff453a');
                                                        }, Text);
                                                        Text.pop();
                                                    });
                                                }
                                            }, If);
                                            If.pop();
                                            Row.pop();
                                        };
                                        this.forEachUpdateFunction(elmtId, item.station.outlets, forEachItemGenFunction);
                                    }, ForEach);
                                    ForEach.pop();
                                    Column.pop();
                                    Column.pop();
                                    ListItem.pop();
                                };
                                this.observeComponentCreation2(itemCreation2, ListItem);
                                ListItem.pop();
                            }
                        };
                        this.forEachUpdateFunction(elmtId, this.getFilteredStations(), forEachItemGenFunction, undefined, true, false);
                    }, ForEach);
                    ForEach.pop();
                    List.pop();
                    Column.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Column.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
class StationPickerUI extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__stationConfig = new SynchedPropertyObjectTwoWayPU(params.stationConfig, this, "stationConfig");
        this.onSaveConfig = undefined;
        this.__allStations = new ObservedPropertyObjectPU([], this, "allStations");
        this.__searchText = new ObservedPropertySimplePU("", this, "searchText");
        this.__selectedIds = new ObservedPropertyObjectPU([], this, "selectedIds");
        this.__isLoading = new ObservedPropertySimplePU(false, this, "isLoading");
        this.__loadingMessage = new ObservedPropertySimplePU("正在加载站点列表…", this, "loadingMessage");
        this.__locationStatus = new ObservedPropertySimplePU("", this, "locationStatus");
        this.locationServiceStateCallback = undefined;
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: StationPickerUI_Params) {
        if (params.onSaveConfig !== undefined) {
            this.onSaveConfig = params.onSaveConfig;
        }
        if (params.allStations !== undefined) {
            this.allStations = params.allStations;
        }
        if (params.searchText !== undefined) {
            this.searchText = params.searchText;
        }
        if (params.selectedIds !== undefined) {
            this.selectedIds = params.selectedIds;
        }
        if (params.isLoading !== undefined) {
            this.isLoading = params.isLoading;
        }
        if (params.loadingMessage !== undefined) {
            this.loadingMessage = params.loadingMessage;
        }
        if (params.locationStatus !== undefined) {
            this.locationStatus = params.locationStatus;
        }
        if (params.locationServiceStateCallback !== undefined) {
            this.locationServiceStateCallback = params.locationServiceStateCallback;
        }
    }
    updateStateVars(params: StationPickerUI_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__stationConfig.purgeDependencyOnElmtId(rmElmtId);
        this.__allStations.purgeDependencyOnElmtId(rmElmtId);
        this.__searchText.purgeDependencyOnElmtId(rmElmtId);
        this.__selectedIds.purgeDependencyOnElmtId(rmElmtId);
        this.__isLoading.purgeDependencyOnElmtId(rmElmtId);
        this.__loadingMessage.purgeDependencyOnElmtId(rmElmtId);
        this.__locationStatus.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__stationConfig.aboutToBeDeleted();
        this.__allStations.aboutToBeDeleted();
        this.__searchText.aboutToBeDeleted();
        this.__selectedIds.aboutToBeDeleted();
        this.__isLoading.aboutToBeDeleted();
        this.__loadingMessage.aboutToBeDeleted();
        this.__locationStatus.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    // 辅助方法：显示Toast消息（API 18+兼容）
    private showToast(message: string, duration: number = 2000): void {
        try {
            this.getUIContext().getPromptAction().openToast({
                message: message,
                duration: duration
            });
        }
        catch (error) {
            console.error('Failed to show toast:', error);
        }
    }
    private __stationConfig: SynchedPropertySimpleOneWayPU<Record<string, number>>;
    get stationConfig() {
        return this.__stationConfig.get();
    }
    set stationConfig(newValue: Record<string, number>) {
        this.__stationConfig.set(newValue);
    }
    // 保存配置的回调函数
    private onSaveConfig?: (newConfig: Record<string, number>) => void;
    private __allStations: ObservedPropertyObjectPU<StationBrief[]>;
    get allStations() {
        return this.__allStations.get();
    }
    set allStations(newValue: StationBrief[]) {
        this.__allStations.set(newValue);
    }
    private __searchText: ObservedPropertySimplePU<string>;
    get searchText() {
        return this.__searchText.get();
    }
    set searchText(newValue: string) {
        this.__searchText.set(newValue);
    }
    private __selectedIds: ObservedPropertyObjectPU<number[]>;
    get selectedIds() {
        return this.__selectedIds.get();
    }
    set selectedIds(newValue: number[]) {
        this.__selectedIds.set(newValue);
    }
    private __isLoading: ObservedPropertySimplePU<boolean>;
    get isLoading() {
        return this.__isLoading.get();
    }
    set isLoading(newValue: boolean) {
        this.__isLoading.set(newValue);
    }
    private __loadingMessage: ObservedPropertySimplePU<string>;
    get loadingMessage() {
        return this.__loadingMessage.get();
    }
    set loadingMessage(newValue: string) {
        this.__loadingMessage.set(newValue);
    }
    private __locationStatus: ObservedPropertySimplePU<string>; // 位置状态提示
    get locationStatus() {
        return this.__locationStatus.get();
    }
    set locationStatus(newValue: string) {
        this.__locationStatus.set(newValue);
    }
    // 定位服务状态监听回调
    private locationServiceStateCallback?: (state: boolean) => void;
    aboutToAppear() {
        this.loadSelectedStations();
        this.fetchAllStations();
        this.setupLocationServiceListener();
    }
    aboutToDisappear() {
        // 移除定位服务状态监听
        if (this.locationServiceStateCallback) {
            try {
                geoLocationManager.off('locationEnabledChange', this.locationServiceStateCallback);
            }
            catch (error) {
                console.error('Failed to remove location service listener:', error);
            }
        }
    }
    // 设置定位服务状态监听
    setupLocationServiceListener() {
        try {
            this.locationServiceStateCallback = (state: boolean) => {
                console.log('📍 Location service state changed:', state);
                // 如果定位服务开启且当前列表为空，自动刷新
                if (state && this.allStations.length === 0 && !this.isLoading) {
                    console.log('🔄 Auto-refreshing stations after location service enabled');
                    this.fetchAllStations();
                }
            };
            geoLocationManager.on('locationEnabledChange', this.locationServiceStateCallback);
            console.log('✅ Location service listener registered');
        }
        catch (error) {
            console.error('Failed to setup location service listener:', error);
        }
    }
    // 加载已选中的站点
    loadSelectedStations() {
        this.selectedIds = Object.values(this.stationConfig);
    }
    // 获取所有可用站点
    async fetchAllStations() {
        this.isLoading = true;
        this.loadingMessage = "正在获取位置信息…";
        try {
            // 获取UIAbilityContext并传递给API，以便在需要时请求权限
            const context = getContext(this) as common.UIAbilityContext;
            // 调用API获取站点，同时获取位置状态
            const result = await ChargerApi.fetchNearbyStations(context);
            this.allStations = result.stations;
            this.locationStatus = result.locationStatus;
            // 检查是否需要提示用户开启定位服务
            if (result.needOpenLocationService) {
                this.showLocationServiceDialog();
            }
            if (this.allStations.length === 0 && !result.needOpenLocationService) {
                this.loadingMessage = "未找到附近充电站";
                console.error('No stations found. Location status:', this.locationStatus);
            }
        }
        catch (error) {
            console.error('Failed to fetch all stations:', error);
            this.loadingMessage = "加载失败，请检查网络";
        }
        this.isLoading = false;
    }
    // 跳转到系统设置的位置服务页面
    openLocationSettings() {
        try {
            const context = getContext(this) as common.UIAbilityContext;
            const want: Want = {
                bundleName: 'com.huawei.hmos.settings',
                abilityName: 'com.huawei.hmos.settings.MainAbility',
                uri: 'location_manager_settings'
            };
            context.startAbility(want)
                .then(() => {
                console.log('✅ Opened location settings');
            })
                .catch((err: BusinessError) => {
                console.error(`Failed to open location settings: ${err.code}, ${err.message}`);
            });
        }
        catch (error) {
            console.error('Failed to open location settings:', error);
        }
    }
    // 切换站点选择状态
    toggleStation(stationId: number) {
        const index = this.selectedIds.indexOf(stationId);
        if (index > -1) {
            // 取消选择
            this.selectedIds.splice(index, 1);
        }
        else {
            // 选择站点
            this.selectedIds.push(stationId);
        }
    }
    // 获取过滤后的站点列表
    getFilteredStations(): StationBrief[] {
        if (!this.searchText.trim()) {
            return this.allStations;
        }
        return this.allStations.filter(station => station.stationName.toLowerCase().includes(this.searchText.toLowerCase()));
    }
    // 保存配置
    saveConfig() {
        if (this.selectedIds.length === 0) {
            this.showToast('请至少选择一个站点', 2000);
            return;
        }
        // 构建新的配置对象
        const newConfig: Record<string, number> = {};
        this.allStations
            .filter(station => this.selectedIds.includes(station.stationId))
            .forEach(station => {
            newConfig[station.stationName] = station.stationId;
        });
        // 检查是否有有效的配置数据
        if (Object.keys(newConfig).length === 0) {
            this.showToast('站点列表加载失败，请检查网络和权限设置', 3000);
            console.error('No valid station data available. allStations:', this.allStations.length);
            return;
        }
        // 调用父组件传递的回调函数来保存配置
        if (this.onSaveConfig) {
            this.onSaveConfig(newConfig);
        }
        else {
            // 如果没有回调函数，显示提示
            this.showToast(`已选择${this.selectedIds.length}个站点，但无法保存配置`, 2000);
            console.error('onSaveConfig callback not provided');
        }
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Index.ets(944:5)", "entry");
            Column.width('100%');
            Column.height('100%');
            Column.backgroundColor('#000000');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 搜索框
            TextInput.create({ placeholder: '搜索站点名称…', text: this.searchText });
            TextInput.debugLine("entry/src/main/ets/pages/Index.ets(946:7)", "entry");
            // 搜索框
            TextInput.onChange((value) => { this.searchText = value; });
            // 搜索框
            TextInput.width('90%');
            // 搜索框
            TextInput.height(40);
            // 搜索框
            TextInput.backgroundColor('#2c2c2e');
            // 搜索框
            TextInput.fontColor(Color.White);
            // 搜索框
            TextInput.borderRadius(8);
            // 搜索框
            TextInput.margin({ top: 16, bottom: 8 });
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // 位置状态提示
            if (this.locationStatus) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.locationStatus);
                        Text.debugLine("entry/src/main/ets/pages/Index.ets(957:9)", "entry");
                        Text.fontColor('#8e8e93');
                        Text.fontSize(12);
                        Text.width('90%');
                        Text.margin({ bottom: 8 });
                    }, Text);
                    Text.pop();
                });
            }
            // 加载状态
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // 加载状态
            if (this.isLoading) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Row.create();
                        Row.debugLine("entry/src/main/ets/pages/Index.ets(966:9)", "entry");
                        Row.width('100%');
                        Row.justifyContent(FlexAlign.Center);
                        Row.padding(20);
                    }, Row);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        LoadingProgress.create();
                        LoadingProgress.debugLine("entry/src/main/ets/pages/Index.ets(967:11)", "entry");
                    }, LoadingProgress);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.loadingMessage);
                        Text.debugLine("entry/src/main/ets/pages/Index.ets(968:11)", "entry");
                        Text.fontColor(Color.White);
                        Text.fontSize(14);
                        Text.margin({ left: 10 });
                    }, Text);
                    Text.pop();
                    Row.pop();
                });
            }
            else if (this.allStations.length === 0) {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        // 空状态提示
                        Column.create({ space: 16 });
                        Column.debugLine("entry/src/main/ets/pages/Index.ets(975:9)", "entry");
                        // 空状态提示
                        Column.width('100%');
                        // 空状态提示
                        Column.layoutWeight(1);
                        // 空状态提示
                        Column.justifyContent(FlexAlign.Center);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('📭');
                        Text.debugLine("entry/src/main/ets/pages/Index.ets(976:11)", "entry");
                        Text.fontSize(48);
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('未找到附近充电站');
                        Text.debugLine("entry/src/main/ets/pages/Index.ets(978:11)", "entry");
                        Text.fontColor(Color.White);
                        Text.fontSize(16);
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        If.create();
                        if (this.locationStatus.includes('默认位置')) {
                            this.ifElseBranchUpdateFunction(0, () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('请确保设备定位服务已开启');
                                    Text.debugLine("entry/src/main/ets/pages/Index.ets(982:13)", "entry");
                                    Text.fontColor('#8e8e93');
                                    Text.fontSize(14);
                                }, Text);
                                Text.pop();
                            });
                        }
                        else {
                            this.ifElseBranchUpdateFunction(1, () => {
                            });
                        }
                    }, If);
                    If.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        If.create();
                        if (this.locationStatus.includes('网络')) {
                            this.ifElseBranchUpdateFunction(0, () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('请检查网络连接');
                                    Text.debugLine("entry/src/main/ets/pages/Index.ets(987:13)", "entry");
                                    Text.fontColor('#8e8e93');
                                    Text.fontSize(14);
                                }, Text);
                                Text.pop();
                            });
                        }
                        // 刷新按钮
                        else {
                            this.ifElseBranchUpdateFunction(1, () => {
                            });
                        }
                    }, If);
                    If.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        // 刷新按钮
                        Button.createWithLabel('刷新');
                        Button.debugLine("entry/src/main/ets/pages/Index.ets(992:11)", "entry");
                        // 刷新按钮
                        Button.backgroundColor('#30d158');
                        // 刷新按钮
                        Button.fontColor(Color.White);
                        // 刷新按钮
                        Button.width(120);
                        // 刷新按钮
                        Button.height(40);
                        // 刷新按钮
                        Button.margin({ top: 16 });
                        // 刷新按钮
                        Button.onClick(() => {
                            this.fetchAllStations();
                        });
                    }, Button);
                    // 刷新按钮
                    Button.pop();
                    // 空状态提示
                    Column.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(2, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        // 站点列表
                        List.create({ space: 8 });
                        List.debugLine("entry/src/main/ets/pages/Index.ets(1007:9)", "entry");
                        // 站点列表
                        List.layoutWeight(1);
                        // 站点列表
                        List.padding({ left: 16, right: 16 });
                    }, List);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const station = _item;
                            {
                                const itemCreation = (elmtId, isInitialRender) => {
                                    ViewStackProcessor.StartGetAccessRecordingFor(elmtId);
                                    ListItem.create(deepRenderFunction, true);
                                    if (!isInitialRender) {
                                        ListItem.pop();
                                    }
                                    ViewStackProcessor.StopGetAccessRecording();
                                };
                                const itemCreation2 = (elmtId, isInitialRender) => {
                                    ListItem.create(deepRenderFunction, true);
                                    ListItem.debugLine("entry/src/main/ets/pages/Index.ets(1009:13)", "entry");
                                };
                                const deepRenderFunction = (elmtId, isInitialRender) => {
                                    itemCreation(elmtId, isInitialRender);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Row.create();
                                        Row.debugLine("entry/src/main/ets/pages/Index.ets(1010:15)", "entry");
                                        Row.width('100%');
                                        Row.padding(16);
                                        Row.backgroundColor('#1c1c1e');
                                        Row.borderRadius(8);
                                    }, Row);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        // 选择框
                                        Checkbox.create({
                                            name: station.stationName,
                                            group: 'stations'
                                        });
                                        Checkbox.debugLine("entry/src/main/ets/pages/Index.ets(1012:17)", "entry");
                                        // 选择框
                                        Checkbox.select(this.selectedIds.includes(station.stationId));
                                        // 选择框
                                        Checkbox.onChange((checked: boolean) => {
                                            this.toggleStation(station.stationId);
                                        });
                                        // 选择框
                                        Checkbox.size({ width: 20, height: 20 });
                                        // 选择框
                                        Checkbox.margin({ right: 12 });
                                    }, Checkbox);
                                    // 选择框
                                    Checkbox.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        // 站点信息
                                        Column.create({ space: 2 });
                                        Column.debugLine("entry/src/main/ets/pages/Index.ets(1024:17)", "entry");
                                        // 站点信息
                                        Column.layoutWeight(1);
                                    }, Column);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(station.stationName);
                                        Text.debugLine("entry/src/main/ets/pages/Index.ets(1025:19)", "entry");
                                        Text.fontColor(Color.White);
                                        Text.fontSize(16);
                                        Text.fontWeight(FontWeight.Medium);
                                    }, Text);
                                    Text.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        If.create();
                                        if (station.address) {
                                            this.ifElseBranchUpdateFunction(0, () => {
                                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                    Text.create(station.address);
                                                    Text.debugLine("entry/src/main/ets/pages/Index.ets(1031:21)", "entry");
                                                    Text.fontColor('#8e8e93');
                                                    Text.fontSize(12);
                                                }, Text);
                                                Text.pop();
                                            });
                                        }
                                        // 显示距离
                                        else {
                                            this.ifElseBranchUpdateFunction(1, () => {
                                            });
                                        }
                                    }, If);
                                    If.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        If.create();
                                        // 显示距离
                                        if (station.formattedDistance) {
                                            this.ifElseBranchUpdateFunction(0, () => {
                                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                    Text.create(`距离: ${station.formattedDistance}`);
                                                    Text.debugLine("entry/src/main/ets/pages/Index.ets(1038:21)", "entry");
                                                    Text.fontColor('#30d158');
                                                    Text.fontSize(11);
                                                }, Text);
                                                Text.pop();
                                            });
                                        }
                                        else {
                                            this.ifElseBranchUpdateFunction(1, () => {
                                            });
                                        }
                                    }, If);
                                    If.pop();
                                    // 站点信息
                                    Column.pop();
                                    Row.pop();
                                    ListItem.pop();
                                };
                                this.observeComponentCreation2(itemCreation2, ListItem);
                                ListItem.pop();
                            }
                        };
                        this.forEachUpdateFunction(elmtId, this.getFilteredStations(), forEachItemGenFunction);
                    }, ForEach);
                    ForEach.pop();
                    // 站点列表
                    List.pop();
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 保存按钮
            Button.createWithLabel(`保存选中站点 (${this.selectedIds.length})`);
            Button.debugLine("entry/src/main/ets/pages/Index.ets(1057:7)", "entry");
            // 保存按钮
            Button.width('90%');
            // 保存按钮
            Button.margin(16);
            // 保存按钮
            Button.backgroundColor('#30d158');
            // 保存按钮
            Button.onClick(() => this.saveConfig());
        }, Button);
        // 保存按钮
        Button.pop();
        Column.pop();
    }
    // 显示开启定位服务弹窗
    showLocationServiceDialog() {
        promptAction.showDialog({
            title: '📍 需要开启定位服务',
            message: '请前往系统设置开启位置服务，以获取附近的充电站信息',
            buttons: [
                { text: '取消', color: '#8e8e93' },
                { text: '去设置', color: '#30d158' }
            ]
        }).then((data: promptAction.ShowDialogSuccessResponse) => {
            if (data.index === 1) {
                // 用户点击"去设置"
                this.openLocationSettings();
            }
        }).catch((err: BusinessError) => {
            console.error('showDialog error:', err);
        });
    }
    rerender() {
        this.updateDirtyElements();
    }
}
function __Text__chipStyle(bgColor: string): void {
    Text.fontSize(10);
    Text.fontColor(Color.White);
    Text.backgroundColor(bgColor);
    Text.padding({ left: 6, right: 6, top: 2, bottom: 2 });
    Text.borderRadius(8);
    Text.margin({ right: 5 });
}
class MapViewerUI extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__scaleValue = new ObservedPropertySimplePU(1.0, this, "scaleValue");
        this.__pinchValue = new ObservedPropertySimplePU(1.0, this, "pinchValue");
        this.__offsetX = new ObservedPropertySimplePU(0, this, "offsetX");
        this.__offsetY = new ObservedPropertySimplePU(0, this, "offsetY");
        this.__lastOffsetX = new ObservedPropertySimplePU(0, this, "lastOffsetX");
        this.__lastOffsetY = new ObservedPropertySimplePU(0, this, "lastOffsetY");
        this.minScale = 0.5;
        this.maxScale = 5.0;
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: MapViewerUI_Params) {
        if (params.scaleValue !== undefined) {
            this.scaleValue = params.scaleValue;
        }
        if (params.pinchValue !== undefined) {
            this.pinchValue = params.pinchValue;
        }
        if (params.offsetX !== undefined) {
            this.offsetX = params.offsetX;
        }
        if (params.offsetY !== undefined) {
            this.offsetY = params.offsetY;
        }
        if (params.lastOffsetX !== undefined) {
            this.lastOffsetX = params.lastOffsetX;
        }
        if (params.lastOffsetY !== undefined) {
            this.lastOffsetY = params.lastOffsetY;
        }
        if (params.minScale !== undefined) {
            this.minScale = params.minScale;
        }
        if (params.maxScale !== undefined) {
            this.maxScale = params.maxScale;
        }
    }
    updateStateVars(params: MapViewerUI_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__scaleValue.purgeDependencyOnElmtId(rmElmtId);
        this.__pinchValue.purgeDependencyOnElmtId(rmElmtId);
        this.__offsetX.purgeDependencyOnElmtId(rmElmtId);
        this.__offsetY.purgeDependencyOnElmtId(rmElmtId);
        this.__lastOffsetX.purgeDependencyOnElmtId(rmElmtId);
        this.__lastOffsetY.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__scaleValue.aboutToBeDeleted();
        this.__pinchValue.aboutToBeDeleted();
        this.__offsetX.aboutToBeDeleted();
        this.__offsetY.aboutToBeDeleted();
        this.__lastOffsetX.aboutToBeDeleted();
        this.__lastOffsetY.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    // 缩放比例
    private __scaleValue: ObservedPropertySimplePU<number>;
    get scaleValue() {
        return this.__scaleValue.get();
    }
    set scaleValue(newValue: number) {
        this.__scaleValue.set(newValue);
    }
    // 上次缩放值（用于双指缩放计算）
    private __pinchValue: ObservedPropertySimplePU<number>;
    get pinchValue() {
        return this.__pinchValue.get();
    }
    set pinchValue(newValue: number) {
        this.__pinchValue.set(newValue);
    }
    // X轴偏移
    private __offsetX: ObservedPropertySimplePU<number>;
    get offsetX() {
        return this.__offsetX.get();
    }
    set offsetX(newValue: number) {
        this.__offsetX.set(newValue);
    }
    // Y轴偏移
    private __offsetY: ObservedPropertySimplePU<number>;
    get offsetY() {
        return this.__offsetY.get();
    }
    set offsetY(newValue: number) {
        this.__offsetY.set(newValue);
    }
    // 上次X偏移（用于单指移动计算）
    private __lastOffsetX: ObservedPropertySimplePU<number>;
    get lastOffsetX() {
        return this.__lastOffsetX.get();
    }
    set lastOffsetX(newValue: number) {
        this.__lastOffsetX.set(newValue);
    }
    // 上次Y偏移（用于单指移动计算）
    private __lastOffsetY: ObservedPropertySimplePU<number>;
    get lastOffsetY() {
        return this.__lastOffsetY.get();
    }
    set lastOffsetY(newValue: number) {
        this.__lastOffsetY.set(newValue);
    }
    // 最小缩放比例
    private minScale: number;
    // 最大缩放比例
    private maxScale: number;
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Index.ets(1120:5)", "entry");
            Column.width('100%');
            Column.height('100%');
            Column.backgroundColor('#1a1a1c');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 提示信息
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(1122:7)", "entry");
            // 提示信息
            Row.width('95%');
            // 提示信息
            Row.padding({ top: 10, bottom: 10 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create("双指缩放 | 单指拖动");
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1123:9)", "entry");
            Text.fontColor('#888888');
            Text.fontSize(12);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Index.ets(1126:9)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`缩放: ${(this.scaleValue * 100).toFixed(0)}%`);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(1127:9)", "entry");
            Text.fontColor('#888888');
            Text.fontSize(12);
        }, Text);
        Text.pop();
        // 提示信息
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 地图显示区域
            Stack.create();
            Stack.debugLine("entry/src/main/ets/pages/Index.ets(1135:7)", "entry");
            // 地图显示区域
            Stack.width('100%');
            // 地图显示区域
            Stack.layoutWeight(1);
            // 地图显示区域
            Stack.clip(true);
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Image.create({ "id": 16777229, "type": 20000, params: [], "bundleName": "com.example.uestc_charger_monitor", "moduleName": "entry" });
            Image.debugLine("entry/src/main/ets/pages/Index.ets(1136:9)", "entry");
            Image.width('100%');
            Image.height('100%');
            Image.objectFit(ImageFit.Contain);
            Image.scale({ x: this.scaleValue, y: this.scaleValue });
            Image.translate({ x: this.offsetX, y: this.offsetY });
            globalThis.Gesture.create(GesturePriority.Low);
            GestureGroup.create(GestureMode.Parallel);
            // 双指缩放手势
            PinchGesture.create({ fingers: 2 });
            // 双指缩放手势
            PinchGesture.onActionStart(() => {
                this.pinchValue = this.scaleValue;
            });
            // 双指缩放手势
            PinchGesture.onActionUpdate((event: GestureEvent) => {
                let newScale = this.pinchValue * event.scale;
                // 限制缩放范围
                newScale = Math.max(this.minScale, Math.min(this.maxScale, newScale));
                this.scaleValue = newScale;
                // 缩放时调整偏移量，保持缩放中心
                this.adjustOffsetOnScale();
            });
            // 双指缩放手势
            PinchGesture.onActionEnd(() => {
                this.pinchValue = this.scaleValue;
            });
            // 双指缩放手势
            PinchGesture.pop();
            // 单指拖动手势
            PanGesture.create({ fingers: 1 });
            // 单指拖动手势
            PanGesture.onActionStart(() => {
                this.lastOffsetX = this.offsetX;
                this.lastOffsetY = this.offsetY;
            });
            // 单指拖动手势
            PanGesture.onActionUpdate((event: GestureEvent) => {
                // 只有放大状态下才允许拖动
                if (this.scaleValue > 1.0) {
                    this.offsetX = this.lastOffsetX + event.offsetX;
                    this.offsetY = this.lastOffsetY + event.offsetY;
                    // 限制偏移范围
                    this.clampOffset();
                }
            });
            // 单指拖动手势
            PanGesture.onActionEnd(() => {
                this.lastOffsetX = this.offsetX;
                this.lastOffsetY = this.offsetY;
            });
            // 单指拖动手势
            PanGesture.pop();
            GestureGroup.pop();
            globalThis.Gesture.pop();
            globalThis.Gesture.create(GesturePriority.Low, GestureMask.IgnoreInternal);
            TapGesture.create({ count: 2 });
            TapGesture.onAction(() => {
                this.resetView();
            });
            TapGesture.pop();
            globalThis.Gesture.pop();
        }, Image);
        // 地图显示区域
        Stack.pop();
        Column.pop();
    }
    // 重置视图
    private resetView() {
        Context.animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
            this.scaleValue = 1.0;
            this.pinchValue = 1.0;
            this.offsetX = 0;
            this.offsetY = 0;
            this.lastOffsetX = 0;
            this.lastOffsetY = 0;
        });
    }
    // 缩放时调整偏移量
    private adjustOffsetOnScale() {
        // 简单处理：缩放时重置偏移
        if (this.scaleValue <= 1.0) {
            this.offsetX = 0;
            this.offsetY = 0;
        }
    }
    // 限制偏移范围
    private clampOffset() {
        // 计算最大允许偏移量
        const maxOffset = (this.scaleValue - 1) * 200;
        this.offsetX = Math.max(-maxOffset, Math.min(maxOffset, this.offsetX));
        this.offsetY = Math.max(-maxOffset, Math.min(maxOffset, this.offsetY));
    }
    rerender() {
        this.updateDirtyElements();
    }
}
registerNamedRoute(() => new MainApp(undefined, {}), "", { bundleName: "com.example.uestc_charger_monitor", moduleName: "entry", pagePath: "pages/Index", pageFullPath: "entry/src/main/ets/pages/Index", integratedHsp: "false", moduleType: "followWithHap" });
