// SegmentedControl.ets - 分段控件组件
import { ThemeColors } from '../theme/ThemeManager';

interface SegmentItem {
  label: string;
  value: number;
}

@Component
export struct SegmentedControl {
  @Prop segments: SegmentItem[] = [];
  @Prop selectedIndex: number = 0;
  @Prop theme: ThemeColors = {} as ThemeColors;
  private onChangeCallback?: (index: number, value: number) => void;

  build() {
    Row() {
      ForEach(this.segments, (segment: SegmentItem, index: number) => {
        Text(segment.label)
          .fontSize(13)
          .fontColor(this.selectedIndex === index ? '#ffffff' : this.theme.textPrimary)
          .fontWeight(this.selectedIndex === index ? FontWeight.Medium : FontWeight.Normal)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .padding({ top: 8, bottom: 8 })
          .backgroundColor(this.selectedIndex === index ? this.theme.accent : 'transparent')
          .borderRadius(8)
          .onClick(() => {
            if (this.onChangeCallback) {
              this.onChangeCallback(index, segment.value);
            }
          })
      }, (segment: SegmentItem) => segment.value.toString())
    }
    .backgroundColor(this.theme.secondaryBackground)
    .borderRadius(10)
    .padding(2)
    .width('100%')
  }
}
