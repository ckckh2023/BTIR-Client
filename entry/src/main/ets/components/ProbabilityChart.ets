import { AppTheme } from '../common/AppTheme';
import { ClassificationResult, SliceProbability } from '../model/TaskModels';
import { probabilitySeries, probabilityThreshold } from '../common/ProbabilityPresentation';

@Component
export struct ProbabilityChart {
  @Prop classification: ClassificationResult;
  @State chartWidth: number = 280;
  @State selected: number = 0;

  private series(): SliceProbability[] { return probabilitySeries(this.classification); }
  private points(): number[][] {
    const series = this.series();
    return series.map((item: SliceProbability, index: number): number[] =>
      [8 + index / Math.max(1, series.length - 1) * (this.chartWidth - 16), 8 + (1 - item.yes_probability) * 104]);
  }
  private selection(): SliceProbability | undefined { return this.series()[Math.min(this.selected, this.series().length - 1)]; }
  private positiveRatio(): string {
    const series = this.series();
    return series.length ? `${(series.filter((item: SliceProbability) => item.yes_probability >= probabilityThreshold(this.classification)).length / series.length * 100).toFixed(0)}%` : '—';
  }

  build() {
    Column({ space: 8 }) {
      Text('切片概率曲线').fontSize(14).fontWeight(FontWeight.Bold).fontColor(AppTheme.text).width('100%')
      Stack({ alignContent: Alignment.TopStart }) {
        Line().startPoint([8, 8 + (1 - probabilityThreshold(this.classification)) * 104])
          .endPoint([this.chartWidth - 8, 8 + (1 - probabilityThreshold(this.classification)) * 104])
          .stroke(AppTheme.muted).strokeWidth(1).strokeDashArray([4, 4])
        Polyline({ width: '100%', height: 120 }).points(this.points()).stroke(AppTheme.primary).strokeWidth(2).fill(Color.Transparent)
        if (this.points().length) {
          Circle().width(7).height(7).fill(AppTheme.primary)
            .position({ x: this.points()[Math.min(this.selected, this.points().length - 1)][0] - 3.5,
              y: this.points()[Math.min(this.selected, this.points().length - 1)][1] - 3.5 })
        }
      }.width('100%').height(120).backgroundColor(AppTheme.subtle).clip(true).borderRadius(AppTheme.buttonRadius)
        .onAreaChange((oldArea: Area, newArea: Area) => { this.chartWidth = Math.max(32, Number(newArea.width)); })
        .onTouch((event: TouchEvent) => {
          if (event.touches.length) this.selected = Math.max(0, Math.min(this.series().length - 1,
            Math.round((event.touches[0].x - 8) / (this.chartWidth - 16) * Math.max(1, this.series().length - 1))));
        })
      if (this.selection()) Text(`切片 ${this.selection()!.slice_index} · 肿瘤概率 ${(this.selection()!.yes_probability * 100).toFixed(1)}%`)
        .fontSize(13).fontColor(AppTheme.primary).width('100%')
      Text(`阳性切片 ${this.positiveRatio()} · 阈值 ${(probabilityThreshold(this.classification) * 100).toFixed(1)}%`)
        .fontSize(12).fontColor(AppTheme.secondary).width('100%')
    }.width('100%').margin({ top: 12 })
  }
}
