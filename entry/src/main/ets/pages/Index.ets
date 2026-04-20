import { CITY_SWITCH_OPTIONS_JSON, LOCATION_STATUS_JSON, TICKET_FEED_JSON } from '../mock/Generic001MockData';

interface LocationStatusData {
  pageTitle: string;
  pageSubtitle: string;
  defaultCity: string;
  detectedCity: string;
  detectedDistrict: string;
  locationLabel: string;
  syncState: string;
  message: string;
  lastUpdated: string;
  switchActionLabel: string;
}

interface CityOption {
  code: string;
  label: string;
  tag: string;
}

interface CityOptionsData {
  options: CityOption[];
}

interface HeroData {
  eyebrow: string;
  headline: string;
  subheadline: string;
}

interface TicketCardData {
  title: string;
  area: string;
  priceLabel: string;
  score: string;
  distance: string;
  highlight: string;
}

interface TicketFeedCityData {
  city: string;
  summary: string;
  tickets: TicketCardData[];
}

interface TicketFeedData {
  quickActions: string[];
  hero: HeroData;
  feeds: TicketFeedCityData[];
}

const LOCATION_STATUS: LocationStatusData = JSON.parse(LOCATION_STATUS_JSON) as LocationStatusData;
const CITY_OPTIONS: CityOptionsData = JSON.parse(CITY_SWITCH_OPTIONS_JSON) as CityOptionsData;
const TICKET_FEED: TicketFeedData = JSON.parse(TICKET_FEED_JSON) as TicketFeedData;

@Entry
@Component
struct Index {
  @State private selectedCity: string = LOCATION_STATUS.defaultCity;
  @State private syncState: string = LOCATION_STATUS.syncState;
  @State private message: string = LOCATION_STATUS.message;
  @State private lastUpdated: string = LOCATION_STATUS.lastUpdated;
  @State private tickets: TicketCardData[] = [];
  @State private summary: string = '';

  aboutToAppear(): void {
    this.applyCity(this.selectedCity, false);
  }

  private applyCity(city: string, byManualSync: boolean): void {
    const feed = this.findFeed(city);
    this.selectedCity = city;
    this.tickets = feed.tickets;
    this.summary = feed.summary;
    this.syncState = city === LOCATION_STATUS.detectedCity ? 'synced' : 'mismatch';

    if (byManualSync && city === LOCATION_STATUS.detectedCity) {
      this.message = `已切换到${LOCATION_STATUS.detectedCity}，首页票务内容已同步当前位置。`;
      this.lastUpdated = '刚刚刷新';
      return;
    }

    this.message = city === LOCATION_STATUS.detectedCity
      ? `首页当前已展示${LOCATION_STATUS.detectedCity}本地票务推荐。`
      : LOCATION_STATUS.message;
    this.lastUpdated = LOCATION_STATUS.lastUpdated;
  }

  private switchToDetectedCity(): void {
    this.applyCity(LOCATION_STATUS.detectedCity, true);
  }

  private findFeed(city: string): TicketFeedCityData {
    for (let index = 0; index < TICKET_FEED.feeds.length; index++) {
      const item = TICKET_FEED.feeds[index];
      if (item.city === city) {
        return item;
      }
    }
    return TICKET_FEED.feeds[0];
  }

  private cityChipBackground(city: string): string {
    if (city === this.selectedCity) {
      return '#1D4ED8';
    }
    if (city === LOCATION_STATUS.detectedCity) {
      return '#DBEAFE';
    }
    return '#FFFFFF';
  }

  private cityChipTextColor(city: string): string {
    if (city === this.selectedCity) {
      return '#FFFFFF';
    }
    if (city === LOCATION_STATUS.detectedCity) {
      return '#1D4ED8';
    }
    return '#334155';
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Column({ space: 10 }) {
          Row() {
            Column({ space: 6 }) {
              Text(LOCATION_STATUS.pageTitle)
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor('#0F172A')

              Text(LOCATION_STATUS.pageSubtitle)
                .fontSize(14)
                .fontColor('#475569')
            }
            .alignItems(HorizontalAlign.Start)

            Blank()

            Column({ space: 4 }) {
              Text('首页城市')
                .fontSize(12)
                .fontColor('#64748B')

              Text(this.selectedCity)
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1D4ED8')
            }
            .alignItems(HorizontalAlign.End)
          }
          .width('100%')

          Text(TICKET_FEED.hero.eyebrow)
            .fontSize(13)
            .fontColor('#B45309')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor('#FFEDD5')
            .borderRadius(16)

          Text(TICKET_FEED.hero.headline)
            .width('100%')
            .fontSize(24)
            .fontWeight(FontWeight.Medium)
            .fontColor('#111827')

          Text(TICKET_FEED.hero.subheadline)
            .width('100%')
            .fontSize(15)
            .lineHeight(22)
            .fontColor('#475569')
        }
        .width('100%')
        .padding(20)
        .borderRadius(28)
        .backgroundColor('#FFF7ED')

        Column({ space: 12 }) {
          Row() {
            Text(LOCATION_STATUS.locationLabel)
              .fontSize(14)
              .fontColor('#64748B')

            Blank()

            Text(this.syncState === 'synced' ? '已同步' : '未同步')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.syncState === 'synced' ? '#166534' : '#B91C1C')
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor(this.syncState === 'synced' ? '#DCFCE7' : '#FEE2E2')
              .borderRadius(14)
          }
          .width('100%')

          Text(`${LOCATION_STATUS.detectedCity} · ${LOCATION_STATUS.detectedDistrict}`)
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')

          Text(this.message)
            .width('100%')
            .fontSize(15)
            .lineHeight(22)
            .fontColor('#334155')

          Text(`最近更新：${this.lastUpdated}`)
            .fontSize(13)
            .fontColor('#64748B')

          Button(LOCATION_STATUS.switchActionLabel)
            .width('100%')
            .height(48)
            .type(ButtonType.Capsule)
            .backgroundColor(this.syncState === 'synced' ? '#16A34A' : '#DC2626')
            .fontColor('#FFFFFF')
            .fontSize(16)
            .onClick(() => {
              this.switchToDetectedCity();
            })
        }
        .width('100%')
        .padding(20)
        .borderRadius(24)
        .backgroundColor('#FFFFFF')

        Column({ space: 12 }) {
          Text('城市切换')
            .width('100%')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')

          Row({ space: 10 }) {
            ForEach(CITY_OPTIONS.options, (item: CityOption) => {
              Button(`${item.label} · ${item.tag}`)
                .type(ButtonType.Capsule)
                .backgroundColor(this.cityChipBackground(item.label))
                .fontColor(this.cityChipTextColor(item.label))
                .fontSize(14)
                .onClick(() => {
                  this.applyCity(item.label, false);
                })
            }, (item: CityOption) => item.code)
          }
          .width('100%')
        }
        .width('100%')

        Column({ space: 10 }) {
          Text('快捷入口')
            .width('100%')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')

          Row({ space: 10 }) {
            ForEach(TICKET_FEED.quickActions, (item: string) => {
              Text(item)
                .fontSize(14)
                .fontColor('#0F172A')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .backgroundColor('#E2E8F0')
                .borderRadius(18)
            }, (item: string) => item)
          }
          .width('100%')
        }
        .width('100%')

        Column({ space: 12 }) {
          Text('门票推荐')
            .width('100%')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')

          Text(this.summary)
            .width('100%')
            .fontSize(14)
            .lineHeight(21)
            .fontColor('#475569')

          ForEach(this.tickets, (item: TicketCardData) => {
            Column({ space: 10 }) {
              Row() {
                Text(item.title)
                  .layoutWeight(1)
                  .fontSize(18)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#111827')

                Text(item.highlight)
                  .fontSize(12)
                  .fontColor('#9A3412')
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .backgroundColor('#FFEDD5')
                  .borderRadius(14)
              }
              .width('100%')

              Text(item.area)
                .width('100%')
                .fontSize(14)
                .fontColor('#64748B')

              Row() {
                Text(item.priceLabel)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#DC2626')

                Blank()

                Text(`评分 ${item.score}`)
                  .fontSize(13)
                  .fontColor('#166534')

                Text(item.distance)
                  .margin({ left: 12 })
                  .fontSize(13)
                  .fontColor('#475569')
              }
              .width('100%')
            }
            .width('100%')
            .padding(18)
            .borderRadius(22)
            .backgroundColor('#FFFFFF')
          }, (item: TicketCardData) => item.title)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 20, bottom: 28 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8FAFC')
  }
}
