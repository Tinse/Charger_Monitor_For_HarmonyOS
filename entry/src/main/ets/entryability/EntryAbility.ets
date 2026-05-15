import { AbilityConstant, ConfigurationConstant, UIAbility, Want, abilityAccessCtrl, bundleManager, Permissions, PermissionRequestResult, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;

// 定位权限列表
const LOCATION_PERMISSIONS: Array<Permissions> = [
  'ohos.permission.LOCATION' as Permissions,
  'ohos.permission.APPROXIMATELY_LOCATION' as Permissions
];

export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', error.message);
    }

    // 检查定位权限状态（不自动申请，遵循最小权限原则）
    await this.checkLocationPermissions();

    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 主窗口被创建，设置主页面
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err) {
        const error = err as BusinessError;
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', error.message);
        return;
      }
    });
  }

  onWindowStageDestroy(): void {
    // 主窗口被销毁，释放UI相关资源
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability从后台回到前台
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
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