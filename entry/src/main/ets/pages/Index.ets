interface AcceptanceItem {
  title: string;
  detail: string;
}

@Entry
@Component
struct Index {
  private readonly deliveryItems: string[] = [
    '生成场景 spec 并写入 dev/spec',
    '拆分独立 mock JSON 文件并集中放置到 dev/mock-data/generic-002',
    '完成 HarmonyOS HAP 构建验证'
  ];

  private readonly acceptanceItems: AcceptanceItem[] = [
    {
      title: '页面语义正确',
      detail: '首页明确表达当前场景没有新增功能实现。'
    },
    {
      title: '数据文件独立',
      detail: '场景元数据、页面说明和验收项拆分为独立 JSON 文件。'
    },
    {
      title: '工程可出包',
      detail: '按照 README 和 build.ps1 指引完成 HAP 构建验证。'
    }
  ];

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Column({ space: 10 }) {
          Text('Generic Scenario 002')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#182431')

          Text('当前场景输入为“什么都不需要实现”，因此应用保留为一个可构建、可验收的通用说明页。')
            .fontSize(15)
            .fontColor('#4E5969')
            .lineHeight(22)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 12 }) {
          Text('NO FEATURE WORK')
            .fontSize(12)
            .fontColor('#0A59F7')
            .fontWeight(FontWeight.Bold)

          Text('无需新增业务实现')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')

          Text('本次交付只保留与场景匹配的静态说明内容，避免扩展不存在的流程或交互。')
            .fontSize(15)
            .fontColor('#475467')
            .lineHeight(22)
        }
        .width('100%')
        .padding(20)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)

        Column({ space: 10 }) {
          Text('本次交付内容')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .textAlign(TextAlign.Start)

          ForEach(this.deliveryItems, (item: string) => {
            Row({ space: 12 }) {
              Text('•')
                .fontSize(18)
                .fontColor('#0A59F7')

              Text(item)
                .layoutWeight(1)
                .fontSize(16)
                .fontColor('#1D2939')
                .lineHeight(22)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
            .backgroundColor('#FFFFFF')
            .borderRadius(18)
            .alignItems(VerticalAlign.Top)
          })
        }
        .width('100%')

        Column({ space: 10 }) {
          Text('验收要点')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .textAlign(TextAlign.Start)

          ForEach(this.acceptanceItems, (item: AcceptanceItem) => {
            Column({ space: 6 }) {
              Text(item.title)
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor('#0F172A')
                .width('100%')
                .textAlign(TextAlign.Start)

              Text(item.detail)
                .fontSize(14)
                .fontColor('#60758A')
                .lineHeight(21)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .backgroundColor('#FFFFFF')
            .borderRadius(18)
          }, (item: AcceptanceItem) => item.title)
        }
        .width('100%')

        Blank()
      }
      .width('100%')
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F3F6FB')
  }
}
