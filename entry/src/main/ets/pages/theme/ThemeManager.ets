// ThemeManager.ets - 主题管理工具类
import preferences from '@ohos.data.preferences';
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
  success: string;              // 成功色（绿色）
  error: string;                // 错误色（红色）

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
  textSecondary: '#8e8e93',
  textTertiary: '#b4b4b4',
  accent: '#0a84ff',
  success: '#30d158',
  error: '#ff453a',
  border: '#3a3a3c',
  overlay: 'rgba(0,0,0,0.5)'
};

// 浅色主题颜色
const LIGHT_COLORS: ThemeColors = {
  background: '#ffffff',        // 纯白色，与系统状态栏/导航栏一致
  cardBackground: '#f2f2f7',    // 卡片背景（浅灰色，与背景有区分）
  secondaryBackground: '#e5e5ea',
  tertiaryBackground: '#d1d1d6',
  textPrimary: '#000000',
  textSecondary: '#8e8e93',
  textTertiary: '#636366',
  accent: '#007aff',
  success: '#34c759',
  error: '#ff3b30',
  border: '#c6c6c8',
  overlay: 'rgba(0,0,0,0.3)'
};

// 主题管理类
export class ThemeManager {
  private static readonly STORE_NAME = 'theme_store';
  private static readonly KEY_THEME_MODE = 'theme_mode';

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

  // 保存主题模式设置
  static async saveThemeMode(context: common.UIAbilityContext, mode: ThemeMode): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, ThemeManager.STORE_NAME);
      await store.put(ThemeManager.KEY_THEME_MODE, mode);
      await store.flush();
      console.log('Theme mode saved:', mode);
    } catch (error) {
      console.error('Failed to save theme mode:', error);
    }
  }

  // 加载主题模式设置
  static async loadThemeMode(context: common.UIAbilityContext): Promise<ThemeMode> {
    try {
      const store = await preferences.getPreferences(context, ThemeManager.STORE_NAME);
      const mode = await store.get(ThemeManager.KEY_THEME_MODE, ThemeMode.SYSTEM);
      return mode as ThemeMode;
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

  // 应用主题模式（保存 + 设置系统颜色模式）
  static async applyThemeMode(context: common.UIAbilityContext, mode: ThemeMode): Promise<void> {
    await ThemeManager.saveThemeMode(context, mode);
    try {
      const applicationContext = context.getApplicationContext();
      applicationContext.setColorMode(ThemeManager.getColorModeConstant(mode));
    } catch (error) {
      console.error('Failed to apply theme mode:', error);
    }
  }
}
