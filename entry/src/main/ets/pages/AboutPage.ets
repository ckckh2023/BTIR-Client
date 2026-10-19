import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppTheme } from '../common/AppTheme';
import { PageHeader } from '../components/PageHeader';

interface ProjectFeature { title: string; description: string; }

@Entry
@Component
struct AboutPage {
  @State errorMessage: string = '';
  @State showRepositories: boolean = false;
  @State twoColumns: boolean = true;
  private features: ProjectFeature[] = [
    { title: '病例上传', description: '四模态 NIfTI 与 DICOM ZIP，自动匹配并校正 FLAIR、T1CE、T1、T2。' },
    { title: '模型分析', description: 'ViT 多切片分类与 SuperLightNet 3D 分割共同提供证据。' },
    { title: '结果展示', description: '综合结论、影像关键特征、分割叠加与区域明细。' },
    { title: '影像查看', description: '手机端提供重点层与邻层预览；网页端支持三视图和 3D 查看。' },
    { title: '随访与任务', description: '病例分组、历史对比、取消重试，以及归档和恢复。' },
    { title: '多用户', description: '账号隔离与任务配额；管理端提供用户、任务和审计管理。' },
    { title: '测试保障', description: '单元测试、接口契约与任务流程回归，覆盖关键操作。' },
    { title: '部署运行', description: '任务队列和数据持久化，支持 CPU、CUDA 与 Linux ROCm。' }
  ];

  private async openLink(url: string): Promise<void> {
    this.errorMessage = '';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await context.startAbility({ action: 'ohos.want.action.viewData', entities: ['entity.system.browsable'], uri: url });
      this.showRepositories = false;
    } catch (error) { this.errorMessage = '无法打开浏览器，请稍后重试'; }
  }

  @Builder
  RepositoryPicker() {
    Column({ space: 16 }) {
      Text('选择代码托管平台').fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppTheme.text).width('100%')
      Button('GitCode').width('100%').height(48).borderRadius(AppTheme.buttonRadius)
        .backgroundColor(AppTheme.primary).fontColor(AppTheme.surface)
        .onClick(() => { this.openLink('https://gitcode.com/ckckh2023/BTIR-BrainTumor-ImageRecognition'); })
      Button('GitHub').width('100%').height(48).borderRadius(AppTheme.buttonRadius)
        .backgroundColor(AppTheme.subtle).fontColor(AppTheme.primary).border({ width: 1, color: AppTheme.border })
        .onClick(() => { this.openLink('https://github.com/ckckh2023/BTIR-BrainTumor-ImageRecognition'); })
      Button('鸿蒙客户端源码').width('100%').height(AppTheme.buttonHeight).borderRadius(AppTheme.buttonRadius)
        .backgroundColor(AppTheme.surface).fontColor(AppTheme.primary)
        .onClick(() => { this.openLink('https://github.com/ckckh2023/BTIR-Client'); })
      if (this.errorMessage) Text(this.errorMessage).fontSize(14).fontColor(AppTheme.danger).width('100%')
    }.width('100%').padding(24)
  }

  build() {
    Column() {
      PageHeader({ title: '关于我们' })
      Scroll() {
        Column({ space: 24 }) {
          Row({ space: 16 }) {
            Image($r('app.media.brand_logo')).width(58).height(58).objectFit(ImageFit.Contain)
              .colorFilter(new ColorFilter([0.1216, 0, 0, 0, 0, 0, 0.2784, 0, 0, 0, 0, 0, 0.4902, 0, 0, 0, 0, 0, 1, 0]))
            Column({ space: 6 }) {
              Text('智瞳医脑').fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppTheme.primary).width('100%')
              Text('脑肿瘤 MRI 影像智能辅助诊断系统').fontSize(14).lineHeight(22).fontColor(AppTheme.secondary).width('100%')
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%').padding(18).borderRadius(AppTheme.cardRadius).border({ width: 1, color: AppTheme.border })
            .linearGradient({ angle: 135, colors: [[AppTheme.selected, 0], [AppTheme.surface, 1]] })

          Column({ space: 12 }) {
            Text('项目简介').fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppTheme.text).width('100%')
            Text('BTIR 是面向四模态脑肿瘤 MRI 的完整分析系统，支持分类、分割与 AI 辅助分析，以及影像特征、切片和随访对比。')
              .fontSize(14).lineHeight(25).fontColor(AppTheme.secondary).width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(['MIT', 'Python', 'FastAPI', 'PyTorch', 'Redis', 'HarmonyOS'], (tag: string) => {
                Text(tag).fontSize(12).fontColor(AppTheme.primary).padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(AppTheme.selected).borderRadius(4).margin({ right: 6, bottom: 6 })
              })
            }.width('100%')
          }.width('100%')

          Column({ space: 12 }) {
            Text('项目能力').fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppTheme.text).width('100%')
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              ForEach(this.features, (feature: ProjectFeature) => {
                Column({ space: 8 }) {
                  Text(feature.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(AppTheme.primary).width('100%')
                  Text(feature.description).fontSize(13).lineHeight(22).fontColor(AppTheme.secondary).width('100%')
                }.width(this.twoColumns ? '48%' : '100%').padding(14).backgroundColor(AppTheme.subtle)
                  .border({ width: 1, color: AppTheme.border }).borderRadius(AppTheme.buttonRadius).margin({ bottom: 12 })
              }, (feature: ProjectFeature) => feature.title)
            }.width('100%').onAreaChange((oldArea: Area, newArea: Area) => { this.twoColumns = Number(newArea.width) >= 330; })
          }.width('100%')

          Column({ space: 14 }) {
            Text('开源与协作').fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppTheme.text).width('100%')
            Text('欢迎查看源码、提交 Issue 或参与贡献。首次体验可先下载测试病例，了解完整分析流程。')
              .fontSize(14).lineHeight(25).fontColor(AppTheme.secondary).width('100%')
            Text('贡献者').fontSize(13).fontColor(AppTheme.secondary).width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(['Songline-music', 'ckckh2023', 'TangibleDreams913'], (name: string) => {
                Button(name).height(AppTheme.buttonHeight).fontSize(13).borderRadius(AppTheme.buttonRadius)
                  .backgroundColor(AppTheme.subtle).fontColor(AppTheme.text).border({ width: 1, color: AppTheme.border })
                  .margin({ right: 6, bottom: 6 }).onClick(() => { this.openLink(`https://github.com/${name}`); })
              })
            }.width('100%')
            Button('选择代码仓库').width('100%').height(AppTheme.buttonHeight).fontSize(14).borderRadius(AppTheme.buttonRadius)
              .backgroundColor(AppTheme.primary).fontColor(AppTheme.surface).onClick(() => { this.showRepositories = true; })
            Button('查看使用说明').width('100%').height(AppTheme.buttonHeight).fontSize(14).borderRadius(AppTheme.buttonRadius)
              .backgroundColor(AppTheme.surface).fontColor(AppTheme.primary).border({ width: 1, color: AppTheme.border })
              .onClick(() => { router.pushUrl({ url: 'pages/SampleDownloadPage' }); })
          }.width('100%')

          if (this.errorMessage) Text(this.errorMessage).fontSize(14).fontColor(AppTheme.danger).width('100%')
        }.width('100%').padding(18).backgroundColor(AppTheme.surface).borderRadius(AppTheme.cardRadius)
          .border({ width: 1, color: AppTheme.border }).margin({ top: 16, bottom: 24 })
      }.width('100%').padding({ left: 16, right: 16 }).layoutWeight(1).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(AppTheme.background)
      .bindSheet($$this.showRepositories, this.RepositoryPicker(), { height: SheetSize.FIT_CONTENT, showClose: true })
  }
}
