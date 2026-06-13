// StatCard.ets - 统计卡片组件
import { ThemeColors } from '../theme/ThemeManager';

@Component
export struct StatCard {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop color: string = '#ffffff';
  @Prop theme: ThemeColors = {} as ThemeColors;

  build() {
    Column() {
      Text(this.value)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.color)

      Text(this.label)
        .fontSize(12)
        .fontColor(this.theme.textSecondary)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Center)
  }
}
