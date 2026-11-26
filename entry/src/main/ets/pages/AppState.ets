// Ability 与页面共享的全局状态键。
interface AppStateKeyNames {
  FOREGROUND: string;
  SYSTEM_DARK_MODE: string;
  WINDOW: string;
}

export const AppStateKeys: AppStateKeyNames = {
  FOREGROUND: 'app.foreground',
  SYSTEM_DARK_MODE: 'systemDarkMode',
  WINDOW: 'app.window'
};
