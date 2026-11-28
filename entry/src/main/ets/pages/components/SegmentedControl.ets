// SegmentedControl.ets - 分段控件组件
import { ThemeColors } from '../theme/ThemeManager';

interface SegmentItem {
  label: string;
  value: number;
}

@ComponentV2
export struct SegmentedControl {
  @Param segments: SegmentItem[] = [];
  @Param selectedIndex: number = 0;
  @Param theme: ThemeColors = {} as ThemeColors;
  @Event onChangeCallback: (index: number, value: number) => void = (_index: number, _value: number) => {};

  build() {
    Row() {
      ForEach(this.segments, (segment: SegmentItem, index: number) => {
        Text(segment.label)
          .fontSize(14).constraintSize({ minHeight: 40 })
          .fontColor(this.selectedIndex === index ? this.theme.infoText : this.theme.textSecondary)
          .fontWeight(this.selectedIndex === index ? FontWeight.Medium : FontWeight.Normal)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .padding({ top: 8, bottom: 8 })
          .backgroundColor(this.selectedIndex === index ? this.theme.infoSurface : Color.Transparent)
          .borderRadius(8)
          .onClick(() => {
            this.onChangeCallback(index, segment.value);
          })
      }, (segment: SegmentItem) => segment.value.toString())
    }
    .backgroundColor(this.theme.background)
    .borderRadius(10)
    .padding(2)
    .width('100%')
  }
}
