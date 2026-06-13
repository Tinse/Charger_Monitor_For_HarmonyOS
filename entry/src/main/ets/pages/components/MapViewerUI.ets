// MapViewerUI.ets - 地图查看组件
import { ThemeManager, ThemeColors } from '../theme/ThemeManager';
import { ApiConfig } from '../ApiConfig';

@Component
export struct MapViewerUI {
  @Prop theme: ThemeColors = ThemeManager.getDarkColors();

  @State scaleValue: number = 1.0;
  @State pinchValue: number = 1.0;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State lastOffsetX: number = 0;
  @State lastOffsetY: number = 0;

  private pinchCenterRatioX: number = 0.5;
  private pinchCenterRatioY: number = 0.5;
  private minScale: number = 0.5;
  private maxScale: number = 5.0;
  private dragSensitivity: number = 2.5;
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
          .scale({ x: this.scaleValue, y: this.scaleValue })
          .translate({ x: this.offsetX, y: this.offsetY })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PinchGesture({ fingers: 2 })
                .onActionStart((event: GestureEvent) => {
                  this.pinchValue = this.scaleValue;
                  this.calculatePinchCenterRatio(event.pinchCenterX, event.pinchCenterY);
                })
                .onActionUpdate((event: GestureEvent) => {
                  const oldScale = this.scaleValue;
                  let newScale = this.pinchValue * event.scale;
                  newScale = Math.max(this.minScale, Math.min(this.maxScale, newScale));
                  this.scaleValue = newScale;
                  this.adjustOffsetOnPinchScale(oldScale, newScale);
                })
                .onActionEnd(() => {
                  this.pinchValue = this.scaleValue;
                }),
              PanGesture({ fingers: 1, direction: PanDirection.All })
                .onActionStart(() => {
                  this.lastOffsetX = this.offsetX;
                  this.lastOffsetY = this.offsetY;
                })
                .onActionUpdate((event: GestureEvent) => {
                  if (this.scaleValue > 1.0) {
                    this.offsetX = this.lastOffsetX + event.offsetX * this.dragSensitivity;
                    this.offsetY = this.lastOffsetY + event.offsetY * this.dragSensitivity;
                    this.clampOffset();
                  }
                })
                .onActionEnd(() => {
                  this.lastOffsetX = this.offsetX;
                  this.lastOffsetY = this.offsetY;
                })
            )
          )
      }
      .width('100%')
      .height('100%')
      .clip(true)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.containerWidth = Number(newValue.width);
        this.containerHeight = Number(newValue.height);
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
      .padding({ left: 16, bottom: 16 })

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
        .onClick(() => {
          const oldScale = this.scaleValue;
          const newScale = Math.min(this.maxScale, this.scaleValue + 0.25);
          this.scaleValue = newScale;
          if (newScale <= 1.0) {
            this.offsetX = 0;
            this.offsetY = 0;
          }
          this.pinchValue = newScale;
        })

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
        .onClick(() => {
          const oldScale = this.scaleValue;
          const newScale = Math.max(this.minScale, this.scaleValue - 0.25);
          this.scaleValue = newScale;
          if (newScale <= 1.0) {
            this.offsetX = 0;
            this.offsetY = 0;
          }
          this.pinchValue = newScale;
        })

        // Divider line
        Row()
          .width(24)
          .height(1)
          .backgroundColor(this.theme.border)
          .margin({ top: 8, bottom: 8 })

        // Reset button
        Button() {
          Text('O')
            .fontSize(16)
            .fontColor(this.theme.textSecondary)
        }
        .width(40)
        .height(40)
        .backgroundColor(this.theme.tertiaryBackground)
        .borderRadius(10)
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
      .margin({ right: 16, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
  }

  private calculatePinchCenterRatio(centerX: number, centerY: number) {
    const displayWidth = this.containerWidth * this.scaleValue;
    const displayHeight = this.containerHeight * this.scaleValue;
    const imgLeft = (this.containerWidth - displayWidth) / 2 + this.offsetX;
    const imgTop = (this.containerHeight - displayHeight) / 2 + this.offsetY;
    this.pinchCenterRatioX = (centerX - imgLeft) / displayWidth;
    this.pinchCenterRatioY = (centerY - imgTop) / displayHeight;
    this.pinchCenterRatioX = Math.max(0, Math.min(1, this.pinchCenterRatioX));
    this.pinchCenterRatioY = Math.max(0, Math.min(1, this.pinchCenterRatioY));
  }

  private adjustOffsetOnPinchScale(oldScale: number, newScale: number) {
    if (newScale <= 1.0) {
      this.offsetX = 0;
      this.offsetY = 0;
      return;
    }
    const oldDisplayWidth = this.containerWidth * oldScale;
    const oldDisplayHeight = this.containerHeight * oldScale;
    const newDisplayWidth = this.containerWidth * newScale;
    const newDisplayHeight = this.containerHeight * newScale;
    const centerInOldImgX = oldDisplayWidth * this.pinchCenterRatioX;
    const centerInOldImgY = oldDisplayHeight * this.pinchCenterRatioY;
    const centerInNewImgX = newDisplayWidth * this.pinchCenterRatioX;
    const centerInNewImgY = newDisplayHeight * this.pinchCenterRatioY;
    const oldImgLeft = (this.containerWidth - oldDisplayWidth) / 2 + this.offsetX;
    const oldImgTop = (this.containerHeight - oldDisplayHeight) / 2 + this.offsetY;
    const centerScreenX = oldImgLeft + centerInOldImgX;
    const centerScreenY = oldImgTop + centerInOldImgY;
    const newImgLeft = centerScreenX - centerInNewImgX;
    const newImgTop = centerScreenY - centerInNewImgY;
    this.offsetX = newImgLeft - (this.containerWidth - newDisplayWidth) / 2;
    this.offsetY = newImgTop - (this.containerHeight - newDisplayHeight) / 2;
    this.clampOffset();
  }

  private resetView() {
    animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.scaleValue = 1.0;
      this.pinchValue = 1.0;
      this.offsetX = 0;
      this.offsetY = 0;
      this.lastOffsetX = 0;
      this.lastOffsetY = 0;
    });
  }

  private clampOffset() {
    const maxOffset = (this.scaleValue - 1) * 300;
    this.offsetX = Math.max(-maxOffset, Math.min(maxOffset, this.offsetX));
    this.offsetY = Math.max(-maxOffset, Math.min(maxOffset, this.offsetY));
  }
}