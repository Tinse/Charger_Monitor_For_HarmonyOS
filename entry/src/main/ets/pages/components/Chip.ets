// Chip.ets - 标签/芯片组件
import { ThemeColors } from '../theme/ThemeManager';

interface ChipOptions {
  label: string;
  selected?: boolean;
  icon?: string;
  theme: ThemeColors;
  onClick?: () => void;
}

@Component
export struct Chip {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  @Prop icon: string = '';
  @Prop theme: ThemeColors = {} as ThemeColors;
  private onClickCallback?: () => void;

  build() {
    Row() {
      if (this.icon) {
        Text(this.icon)
          .fontSize(14)
          .margin({ right: 4 })
      }

      Text(this.label)
        .fontSize(13)
        .fontColor(this.selected ? '#ffffff' : this.theme.textPrimary)
        .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(this.selected ? this.theme.accent : this.theme.secondaryBackground)
    .borderRadius(16)
    .onClick(() => {
      if (this.onClickCallback) {
        this.onClickCallback();
      }
    })
  }
}
