// SearchBar.ets - 胶囊搜索栏组件
import { ThemeColors } from '../theme/ThemeManager';

@Component
export struct SearchBar {
  @Prop placeholder: string = '搜索...';
  @Prop theme: ThemeColors = {} as ThemeColors;
  @Prop value: string = '';
  private onChangeCallback?: (value: string) => void;
  private onSubmitCallback?: (value: string) => void;

  build() {
    Row() {
      Text('🔍')
        .fontSize(14)
        .margin({ right: 8 })

      TextInput({ placeholder: this.placeholder, text: this.value })
        .layoutWeight(1)
        .height(36)
        .backgroundColor('transparent')
        .fontColor(this.theme.textPrimary)
        .placeholderColor(this.theme.textSecondary)
        .fontSize(14)
        .onChange((value: string) => {
          if (this.onChangeCallback) {
            this.onChangeCallback(value);
          }
        })
        .onSubmit(() => {
          if (this.onSubmitCallback) {
            this.onSubmitCallback(this.value);
          }
        })
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(this.theme.secondaryBackground)
    .borderRadius(20)
    .width('100%')
  }
}
