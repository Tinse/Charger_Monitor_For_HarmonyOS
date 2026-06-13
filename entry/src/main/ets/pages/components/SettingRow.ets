// SettingRow.ets - 设置行组件
import { ThemeColors } from '../theme/ThemeManager';

@Component
export struct SettingRow {
  @Prop icon: string = '';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop theme: ThemeColors = {} as ThemeColors;
  @Prop showArrow: boolean = false;
  @Prop showDivider: boolean = true;
  private onClickCallback?: () => void;
  @Builder
  trailingBuilder(): void {}

  build() {
    Column() {
      Row() {
        // 左侧图标
        if (this.icon) {
          Text(this.icon)
            .fontSize(20)
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .margin({ right: 12 })
        }

        // 标题和副标题
        Column() {
          Text(this.title)
            .fontSize(15)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Normal)

          if (this.subtitle) {
            Text(this.subtitle)
              .fontSize(12)
              .fontColor(this.theme.textSecondary)
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 右侧控件
        if (this.trailingBuilder) {
          this.trailingBuilder()
        }

        // 箭头
        if (this.showArrow) {
          Text('>')
            .fontSize(14)
            .fontColor(this.theme.textTertiary)
            .margin({ left: 8 })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .onClick(() => {
        if (this.onClickCallback) {
          this.onClickCallback();
        }
      })

      // 分隔线
      if (this.showDivider) {
        Divider()
          .color(this.theme.border)
          .margin({ left: 56, right: 16 })
      }
    }
  }
}
