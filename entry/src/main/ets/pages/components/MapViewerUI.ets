// MapViewerUI.ets - 地图查看组件
import { ThemeManager, ThemeColors } from '../theme/ThemeManager';

@Component
export struct MapViewerUI {
  @Prop theme: ThemeColors = ThemeManager.getDarkColors();

  @State scaleValue: number = 1.0;
  @State pinchValue: number = 1.0;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State lastOffsetX: number = 0;
  @State lastOffsetY: number = 0;

  private pinching: boolean = false;
  private panInterrupted: boolean = false;
  private pinchCenterRatioX: number = 0.5;
  private pinchCenterRatioY: number = 0.5;
  private minScale: number = 0.5;
  private maxScale: number = 5.0;
  // 使用资源的实际比例计算可拖动边界，缩放与手指位移保持一比一。
  private imageWidth: number = 2938;
  private imageHeight: number = 3000;
  private containerWidth: number = 0;
  private containerHeight: number = 0;

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      // Map image with gestures
      Stack() {
        Image($r('app.media.map'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .accessibilityText('清水河校区充电站分布图，可双指缩放、单指拖动')
          .onComplete(event => {
            if (event && event.width > 0 && event.height > 0) {
              this.imageWidth = event.width;
              this.imageHeight = event.height;
              this.clampOffset();
            }
          })
          .scale({ x: this.scaleValue, y: this.scaleValue })
          .translate({ x: this.offsetX, y: this.offsetY })
      }
      .width('100%')
      .height('100%')
      .clip(true)
      .gesture(
        GestureGroup(GestureMode.Parallel,
          PinchGesture({ fingers: 2 })
            .onActionStart((event: GestureEvent) => {
              this.pinchValue = this.scaleValue;
              this.pinching = true;
              this.panInterrupted = true;
              this.calculatePinchCenterRatio(event.pinchCenterX, event.pinchCenterY);
            })
            .onActionUpdate((event: GestureEvent) => {
              let newScale = this.pinchValue * event.scale;
              newScale = Math.max(this.minScale, Math.min(this.maxScale, newScale));
              this.scaleValue = newScale;
              this.adjustOffsetOnPinchScale(event.pinchCenterX, event.pinchCenterY);
            })
            .onActionEnd(() => { this.pinching = false; })
            .onActionCancel(() => { this.pinching = false; }),
          PanGesture({ fingers: 1, direction: PanDirection.All })
            .onActionStart(() => {
              this.panInterrupted = this.pinching;
              this.lastOffsetX = this.offsetX;
              this.lastOffsetY = this.offsetY;
            })
            .onActionUpdate((event: GestureEvent) => {
              if (!this.panInterrupted && this.scaleValue > 1.0) {
                this.offsetX = this.lastOffsetX + event.offsetX;
                this.offsetY = this.lastOffsetY + event.offsetY;
                this.clampOffset();
              }
            })
            .onActionEnd(() => {
              this.lastOffsetX = this.offsetX;
              this.lastOffsetY = this.offsetY;
            })
        )
      )
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.containerWidth = Number(newValue.width);
        this.containerHeight = Number(newValue.height);
        this.clampOffset();
        this.lastOffsetX = this.offsetX;
        this.lastOffsetY = this.offsetY;
      })

      // Zoom level badge in bottom-left corner
      Row() {
        Text(`${(this.scaleValue * 100).toFixed(0)}%`)
          .fontSize(12)
          .fontColor(this.theme.textSecondary)
          .fontWeight(FontWeight.Medium)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(this.theme.cardBackground)
          .borderRadius(8)
          .border({ width: 0.5, color: this.theme.border })
      }
      .position({ left: 16, bottom: 120 })

      // Floating toolbar card in bottom-right corner
      Column() {
        // Zoom in button
        Button() {
          Text('+')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.textPrimary)
        }
        .width(40)
        .height(40)
        .backgroundColor(this.theme.tertiaryBackground)
        .borderRadius(10)
        .enabled(this.scaleValue < this.maxScale)
        .accessibilityText('放大地图')
        .onClick(() => this.setScale(this.scaleValue + 0.25))

        // Current zoom percentage text
        Text(`${(this.scaleValue * 100).toFixed(0)}%`)
          .fontSize(11)
          .fontColor(this.theme.textSecondary)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 6, bottom: 6 })
          .textAlign(TextAlign.Center)
          .width(40)

        // Zoom out button
        Button() {
          Text('-')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme.textPrimary)
        }
        .width(40)
        .height(40)
        .backgroundColor(this.theme.tertiaryBackground)
        .borderRadius(10)
        .enabled(this.scaleValue > this.minScale)
        .accessibilityText('缩小地图')
        .onClick(() => this.setScale(this.scaleValue - 0.25))

        // Divider line
        Row()
          .width(24)
          .height(1)
          .backgroundColor(this.theme.border)
          .margin({ top: 8, bottom: 8 })

        // Reset button
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
            .fontSize(20)
            .fontColor([this.theme.textPrimary])
        }
        .width(40)
        .height(40)
        .backgroundColor(this.theme.tertiaryBackground)
        .borderRadius(10)
        .accessibilityText('复位地图')
        .onClick(() => {
          this.resetView();
        })
      }
      .padding(10)
      .backgroundColor(this.theme.cardBackground)
      .borderRadius(14)
      .shadow({
        radius: 12,
        color: '#1A000000',
        offsetX: 0,
        offsetY: 2
      })
      .border({ width: 0.5, color: this.theme.border })
      .margin({ right: 16, bottom: 120 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }

  private calculatePinchCenterRatio(centerX: number, centerY: number) {
    const displayWidth = this.getFittedWidth() * this.scaleValue;
    const displayHeight = this.getFittedHeight() * this.scaleValue;
    if (displayWidth <= 0 || displayHeight <= 0) return;
    const imgLeft = (this.containerWidth - displayWidth) / 2 + this.offsetX;
    const imgTop = (this.containerHeight - displayHeight) / 2 + this.offsetY;
    this.pinchCenterRatioX = (centerX - imgLeft) / displayWidth;
    this.pinchCenterRatioY = (centerY - imgTop) / displayHeight;
    this.pinchCenterRatioX = Math.max(0, Math.min(1, this.pinchCenterRatioX));
    this.pinchCenterRatioY = Math.max(0, Math.min(1, this.pinchCenterRatioY));
  }

  private adjustOffsetOnPinchScale(centerX: number, centerY: number) {
    const scaledWidth = this.getFittedWidth() * this.scaleValue;
    const scaledHeight = this.getFittedHeight() * this.scaleValue;
    this.offsetX = centerX - this.containerWidth / 2 + (0.5 - this.pinchCenterRatioX) * scaledWidth;
    this.offsetY = centerY - this.containerHeight / 2 + (0.5 - this.pinchCenterRatioY) * scaledHeight;
    this.clampOffset();
  }

  private resetView() {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.scaleValue = 1.0;
      this.pinchValue = 1.0;
      this.offsetX = 0;
      this.offsetY = 0;
      this.lastOffsetX = 0;
      this.lastOffsetY = 0;
    });
  }

  private setScale(scale: number): void {
    this.scaleValue = Math.max(this.minScale, Math.min(this.maxScale, scale));
    this.pinchValue = this.scaleValue;
    this.clampOffset();
    this.lastOffsetX = this.offsetX;
    this.lastOffsetY = this.offsetY;
  }

  private getFittedWidth(): number {
    if (this.containerWidth <= 0 || this.containerHeight <= 0) return 0;
    return Math.min(this.containerWidth, this.containerHeight * this.imageWidth / this.imageHeight);
  }

  private getFittedHeight(): number {
    if (this.containerWidth <= 0 || this.containerHeight <= 0) return 0;
    return Math.min(this.containerHeight, this.containerWidth * this.imageHeight / this.imageWidth);
  }

  private clampOffset(): void {
    const maxOffsetX = Math.max(0, (this.getFittedWidth() * this.scaleValue - this.containerWidth) / 2);
    const maxOffsetY = Math.max(0, (this.getFittedHeight() * this.scaleValue - this.containerHeight) / 2);
    this.offsetX = Math.max(-maxOffsetX, Math.min(maxOffsetX, this.offsetX));
    this.offsetY = Math.max(-maxOffsetY, Math.min(maxOffsetY, this.offsetY));
  }
}
