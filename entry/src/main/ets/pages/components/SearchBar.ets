// SearchBar.ets - 胶囊搜索栏组件
import { ThemeColors } from '../theme/ThemeManager';

@ComponentV2
export struct SearchBar {
  @Param placeholder: string = '搜索...';
  @Param theme: ThemeColors = {} as ThemeColors;
  @Param value: string = '';
  @Event onChangeCallback: (value: string) => void = (_value: string) => {};
  @Event onSubmitCallback: (value: string) => void = (_value: string) => {};

  build() {
    Row() {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(16).fontColor([this.theme.textSecondary])
        .margin({ right: 8 })

      TextInput({ placeholder: this.placeholder, text: this.value })
        .layoutWeight(1)
        .height(40).padding({ left: 0, right: 0 })
        .backgroundColor('transparent')
        .fontColor(this.theme.textPrimary)
        .placeholderColor(this.theme.textSecondary)
        .fontSize(13)
        .onChange((value: string) => {
          this.onChangeCallback(value);
        })
        .onSubmit(() => {
          this.onSubmitCallback(this.value);
        })
    }
    .padding({ left: 14, right: 12 })
    .backgroundColor(this.theme.secondaryBackground)
    .borderRadius(12)
    .width('100%')
  }
}
