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
        .fontSize(18).fontColor([this.theme.textSecondary])
        .margin({ right: 8 })

      TextInput({ placeholder: this.placeholder, text: this.value })
        .layoutWeight(1)
        .height(36)
        .backgroundColor('transparent')
        .fontColor(this.theme.textPrimary)
        .placeholderColor(this.theme.textSecondary)
        .fontSize(14)
        .onChange((value: string) => {
          this.onChangeCallback(value);
        })
        .onSubmit(() => {
          this.onSubmitCallback(this.value);
        })
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(this.theme.secondaryBackground)
    .borderRadius(20)
    .width('100%')
  }
}
