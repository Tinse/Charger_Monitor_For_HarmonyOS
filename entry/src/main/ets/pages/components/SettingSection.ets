// SettingSection.ets - 设置分组组件
import { ThemeColors } from '../theme/ThemeManager';

@Component
export struct SettingSection {
  @Prop title: string = '';
  @Prop theme: ThemeColors = {} as ThemeColors;
  @Builder
  contentBuilder(): void {}

  build() {
    Column() {
      // 分组标题
      if (this.title) {
        Text(this.title)
          .fontSize(12)
          .fontColor(this.theme.textSecondary)
          .fontWeight(FontWeight.Normal)
          .padding({ left: 16, right: 16, top: 8, bottom: 4 })
          .width('90%')
      }

      // 内容卡片
      Column() {
        if (this.contentBuilder) {
          this.contentBuilder()
        }
      }
      .width('90%')
      .backgroundColor(this.theme.cardBackground)
      .borderRadius(12)
      .clip(true)
    }
    .width('100%')
    .margin({ bottom: 16 })
  }
}
