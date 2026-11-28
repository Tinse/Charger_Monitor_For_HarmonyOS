// ThemeManager.ets - 主题管理工具类
import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';

// 主题模式枚举
export enum ThemeMode {
  SYSTEM = 0,  // 跟随系统
  DARK = 1,    // 深色模式
  LIGHT = 2    // 浅色模式
}

// 主题颜色接口
export interface ThemeColors {
  // 背景色
  background: string;           // 页面主背景
  cardBackground: string;       // 卡片背景
  secondaryBackground: string;  // 次级背景（如输入框）
  tertiaryBackground: string;   // 三级背景（如按钮）

  // 文字颜色
  textPrimary: string;          // 主要文字
  textSecondary: string;        // 次要文字
  textTertiary: string;         // 三级文字（提示）

  // 强调色
  accent: string;               // 主强调色（蓝色）
  onAccent: string;             // 实心主按钮前景
  success: string;              // 成功色（绿色）
  error: string;                // 错误色（红色）
  warning: string;              // 警示圆点
  infoSurface: string;
  infoText: string;
  successSurface: string;
  successText: string;
  warningSurface: string;
  warningText: string;
  errorSurface: string;
  errorText: string;

  // 其他
  border: string;               // 边框色
  overlay: string;              // 遮罩层
}

// 深色主题颜色
const DARK_COLORS: ThemeColors = {
  background: '#000000',
  cardBackground: '#1c1c1e',
  secondaryBackground: '#2c2c2e',
  tertiaryBackground: '#48484a',
  textPrimary: '#ffffff',
  textSecondary: '#a1a4aa',
  textTertiary: '#b4b4b4',
  accent: '#0a84ff',
  onAccent: '#ffffff',
  success: '#30d158',
  error: '#ff453a',
  warning: '#ffd60a',
  infoSurface: 'rgba(10,132,255,0.15)',
  infoText: '#0a84ff',
  successSurface: 'rgba(48,209,88,0.15)',
  successText: '#30d158',
  warningSurface: 'rgba(255,214,10,0.15)',
  warningText: '#ffd60a',
  errorSurface: 'rgba(255,69,58,0.15)',
  errorText: '#ff453a',
  border: '#3a3a3c',
  overlay: 'rgba(0,0,0,0.5)'
};

// 浅色主题颜色
const LIGHT_COLORS: ThemeColors = {
  background: '#f1f3f5',        // 浅灰画布搭配白色分组卡片
  cardBackground: '#ffffff',    // 分组卡片
  secondaryBackground: '#e7e9ec',
  tertiaryBackground: '#d1d1d6',
  textPrimary: '#000000',
  textSecondary: '#737780',
  textTertiary: '#636366',
  accent: '#0a59f7',
  onAccent: '#ffffff',
  success: '#34c759',
  error: '#ff3b30',
  warning: '#ffd60a',
  infoSurface: 'rgba(10,132,255,0.15)',
  infoText: '#0a59f7',
  successSurface: 'rgba(48,209,88,0.15)',
  successText: '#34c759',
  warningSurface: 'rgba(255,214,10,0.15)',
  warningText: '#806000',
  errorSurface: 'rgba(255,69,58,0.15)',
  errorText: '#ff3b30',
  border: '#c6c6c8',
  overlay: 'rgba(0,0,0,0.3)'
};

// 主题管理类
export class ThemeManager {
  private static readonly STORE_NAME = 'theme_store';
  private static readonly KEY_THEME_MODE = 'theme_mode';
  private static readonly KEY_IMMERSIVE_ENABLED = 'immersive_enabled';

  // 获取主题颜色
  static getColors(isDark: boolean): ThemeColors {
    return isDark ? DARK_COLORS : LIGHT_COLORS;
  }

  // 获取深色主题颜色
  static getDarkColors(): ThemeColors {
    return DARK_COLORS;
  }

  // 获取浅色主题颜色
  static getLightColors(): ThemeColors {
    return LIGHT_COLORS;
  }

  private static async savePreference(context: common.UIAbilityContext, key: string,
    value: number | boolean, previous: number | boolean): Promise<void> {
    let store: preferences.Preferences | undefined;
    let changed: boolean = false;
    try {
      store = await preferences.getPreferences(context, ThemeManager.STORE_NAME);
      await store.put(key, value);
      changed = true;
      await store.flush();
    } catch (error) {
      console.error('Failed to persist appearance preference:', error);
      if (store && changed) {
        // put updates the shared cache first. Restore it before a later flush can persist this failed change.
        try {
          await store.put(key, previous);
          await store.flush();
        } catch (rollbackError) {
          console.error('Failed to restore appearance preference:', rollbackError);
        }
      }
      throw new Error('外观设置保存失败');
    }
  }

  // 加载主题模式设置
  static async loadThemeMode(context: common.UIAbilityContext): Promise<ThemeMode> {
    try {
      const store = await preferences.getPreferences(context, ThemeManager.STORE_NAME);
      const mode = await store.get(ThemeManager.KEY_THEME_MODE, ThemeMode.SYSTEM);
      if (mode === ThemeMode.LIGHT) return ThemeMode.LIGHT;
      if (mode === ThemeMode.DARK) return ThemeMode.DARK;
      return ThemeMode.SYSTEM;
    } catch (error) {
      console.error('Failed to load theme mode:', error);
      return ThemeMode.SYSTEM;
    }
  }

  // 解析是否为深色模式
  static resolveIsDark(themeMode: ThemeMode, systemDarkMode: boolean): boolean {
    if (themeMode === ThemeMode.SYSTEM) {
      return systemDarkMode;
    }
    return themeMode === ThemeMode.DARK;
  }

  // 获取 ConfigurationConstant.ColorMode
  static getColorModeConstant(themeMode: ThemeMode): ConfigurationConstant.ColorMode {
    if (themeMode === ThemeMode.SYSTEM) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    } else if (themeMode === ThemeMode.DARK) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
  }

  static async loadImmersiveEnabled(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const store = await preferences.getPreferences(context, ThemeManager.STORE_NAME);
      const enabled = await store.get(ThemeManager.KEY_IMMERSIVE_ENABLED, true);
      return typeof enabled === 'boolean' ? enabled : true;
    } catch (error) {
      console.error('Failed to load immersive preference:', error);
      return true;
    }
  }

  static async saveImmersiveEnabled(context: common.UIAbilityContext, enabled: boolean, previous: boolean): Promise<void> {
    await ThemeManager.savePreference(context, ThemeManager.KEY_IMMERSIVE_ENABLED, enabled, previous);
  }

  static applyThemeMode(context: common.UIAbilityContext, mode: ThemeMode): void {
    try {
      context.getApplicationContext().setColorMode(ThemeManager.getColorModeConstant(mode));
    } catch (error) {
      console.error('Failed to apply system color mode:', error);
      throw new Error('系统主题切换失败');
    }
  }

  static async changeThemeMode(context: common.UIAbilityContext, mode: ThemeMode, previous: ThemeMode): Promise<void> {
    ThemeManager.applyThemeMode(context, mode);
    try {
      await ThemeManager.savePreference(context, ThemeManager.KEY_THEME_MODE, mode, previous);
    } catch (error) {
      ThemeManager.applyThemeMode(context, previous);
      throw new Error('主题设置保存失败');
    }
  }
}
