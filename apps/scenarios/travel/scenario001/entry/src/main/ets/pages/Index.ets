import { BannerItem, DestinationCard, HomeQuickEntry, OrderCard, SearchFormData, ServiceType, TravelPackage, TravelProduct } from '../models/AppModels';
import { homeBanners, homeQuickEntries, personalizedDeals, popularDestinations } from '../mock/homeMock';
import { travelProductsMock } from '../mock/inventoryMock';
import { memberProfileMock, orderMockList } from '../mock/orderMock';
import { commonCities, defaultSearchForm, filterOptions, serviceLabels, sortOptions } from '../mock/searchMock';

type ScreenKey = 'home' | 'search' | 'results' | 'detail' | 'booking' | 'payment' | 'orders' | 'service' | 'profile' | 'orderDetail';

function cloneOrder(order: OrderCard): OrderCard {
  return {
    id: order.id,
    serviceType: order.serviceType,
    title: order.title,
    subtitle: order.subtitle,
    amount: order.amount,
    status: order.status,
    travelDate: order.travelDate,
    actionLabel: order.actionLabel,
    reminder: order.reminder
  };
}

function cloneSearchForm(form: SearchFormData): SearchFormData {
  return {
    serviceType: form.serviceType,
    fromCity: form.fromCity,
    toCity: form.toCity,
    departDate: form.departDate,
    returnDate: form.returnDate,
    checkInDate: form.checkInDate,
    checkOutDate: form.checkOutDate,
    travelers: form.travelers,
    rooms: form.rooms,
    cabin: form.cabin
  };
}

@Entry
@Component
struct Index {
  @State private currentScreen: ScreenKey = 'home';
  @State private currentTab: number = 0;
  @State private currentService: ServiceType = 'hotel';
  @State private searchForm: SearchFormData = cloneSearchForm(defaultSearchForm);
  @State private selectedSort: string = '推荐优先';
  @State private selectedFilters: string[] = ['可取消', '高评分'];
  @State private selectedProductId: string = 'hotel-1';
  @State private selectedPackageId: string = 'hotel-1-p1';
  @State private selectedOrderId: string = 'order-1001';
  @State private draftTraveler: string = '王晨';
  @State private draftPhone: string = '138 0013 8000';
  @State private invoiceRequired: boolean = true;
  @State private paymentMethod: string = '微信支付';
  @State private paymentCountdown: number = 14;
  @State private orders: OrderCard[] = [
    cloneOrder(orderMockList[0]),
    cloneOrder(orderMockList[1]),
    cloneOrder(orderMockList[2])
  ];

  aboutToAppear(): void {
    this.applyServiceToForm(this.currentService);
  }

  private applyServiceToForm(serviceType: ServiceType): void {
    this.currentService = serviceType;
    this.searchForm = cloneSearchForm(defaultSearchForm);
    this.searchForm.serviceType = serviceType;
    if (serviceType === 'hotel' || serviceType === 'ticket' || serviceType === 'vacation') {
      this.searchForm.fromCity = '';
    }
  }

  private enterSearch(serviceType: ServiceType): void {
    this.currentTab = 0;
    this.applyServiceToForm(serviceType);
    this.currentScreen = 'search';
  }

  private executeSearch(): void {
    this.currentScreen = 'results';
  }

  private openProduct(productId: string): void {
    this.selectedProductId = productId;
    const product: TravelProduct | undefined = this.getSelectedProduct();
    if (product !== undefined && product.packages.length > 0) {
      this.selectedPackageId = product.packages[0].id;
    }
    this.currentScreen = 'detail';
  }

  private startBooking(packageId: string): void {
    this.selectedPackageId = packageId;
    this.currentScreen = 'booking';
  }

  private submitBooking(): void {
    this.paymentCountdown = 14;
    this.currentScreen = 'payment';
  }

  private completePayment(): void {
    const product: TravelProduct | undefined = this.getSelectedProduct();
    const pkg: TravelPackage | undefined = this.getSelectedPackage();
    if (product === undefined || pkg === undefined) {
      return;
    }
    const newOrder: OrderCard = {
      id: `order-${1000 + this.orders.length + 1}`,
      serviceType: product.serviceType,
      title: product.title,
      subtitle: pkg.name,
      amount: this.getFinalAmount(),
      status: '待出行',
      travelDate: this.getTravelDateText(),
      actionLabel: '查看订单',
      reminder: '订单已支付成功，行程提醒将同步展示'
    };
    const nextOrders: OrderCard[] = [cloneOrder(newOrder)];
    for (let i = 0; i < this.orders.length; i++) {
      nextOrders.push(cloneOrder(this.orders[i]));
    }
    this.orders = nextOrders;
    this.selectedOrderId = newOrder.id;
    this.currentTab = 1;
    this.currentScreen = 'orders';
  }

  private goTab(tabIndex: number): void {
    this.currentTab = tabIndex;
    if (tabIndex === 0) {
      this.currentScreen = 'home';
    } else if (tabIndex === 1) {
      this.currentScreen = 'orders';
    } else if (tabIndex === 2) {
      this.currentScreen = 'service';
    } else {
      this.currentScreen = 'profile';
    }
  }

  private selectFilter(filter: string): void {
    const next: string[] = [];
    let existed: boolean = false;
    for (let i = 0; i < this.selectedFilters.length; i++) {
      if (this.selectedFilters[i] === filter) {
        existed = true;
      } else {
        next.push(this.selectedFilters[i]);
      }
    }
    if (!existed) {
      next.push(filter);
    }
    this.selectedFilters = next;
  }

  private selectOrder(orderId: string): void {
    this.selectedOrderId = orderId;
    this.currentScreen = 'orderDetail';
  }

  private getSelectedProduct(): TravelProduct | undefined {
    for (let i = 0; i < travelProductsMock.length; i++) {
      if (travelProductsMock[i].id === this.selectedProductId) {
        return travelProductsMock[i];
      }
    }
    return undefined;
  }

  private getSelectedPackage(): TravelPackage | undefined {
    const product: TravelProduct | undefined = this.getSelectedProduct();
    if (product === undefined) {
      return undefined;
    }
    for (let i = 0; i < product.packages.length; i++) {
      if (product.packages[i].id === this.selectedPackageId) {
        return product.packages[i];
      }
    }
    return product.packages[0];
  }

  private getSelectedOrder(): OrderCard | undefined {
    for (let i = 0; i < this.orders.length; i++) {
      if (this.orders[i].id === this.selectedOrderId) {
        return this.orders[i];
      }
    }
    return undefined;
  }

  private getCurrentServiceLabel(): string {
    if (this.currentService === 'hotel') {
      return serviceLabels.hotel;
    }
    if (this.currentService === 'flight') {
      return serviceLabels.flight;
    }
    if (this.currentService === 'train') {
      return serviceLabels.train;
    }
    if (this.currentService === 'ticket') {
      return serviceLabels.ticket;
    }
    return serviceLabels.vacation;
  }

  private getSafeSelectedProduct(): TravelProduct {
    const product: TravelProduct | undefined = this.getSelectedProduct();
    if (product !== undefined) {
      return product;
    }
    return travelProductsMock[0];
  }

  private getSafeSelectedPackage(): TravelPackage {
    const pkg: TravelPackage | undefined = this.getSelectedPackage();
    if (pkg !== undefined) {
      return pkg;
    }
    return this.getSafeSelectedProduct().packages[0];
  }

  private getSafeSelectedOrder(): OrderCard {
    const order: OrderCard | undefined = this.getSelectedOrder();
    if (order !== undefined) {
      return order;
    }
    return this.orders[0];
  }

  private getProductsByCurrentService(): TravelProduct[] {
    const matched: TravelProduct[] = [];
    for (let i = 0; i < travelProductsMock.length; i++) {
      const product: TravelProduct = travelProductsMock[i];
      if (product.serviceType === this.currentService) {
        matched.push(product);
      }
    }
    const filtered: TravelProduct[] = [];
    for (let i = 0; i < matched.length; i++) {
      const product: TravelProduct = matched[i];
      let accepted: boolean = true;
      for (let j = 0; j < this.selectedFilters.length; j++) {
        const filter: string = this.selectedFilters[j];
        if (filter === '可取消' && product.policyTag.indexOf('取消') < 0) {
          accepted = false;
        }
        if (filter === '高评分' && product.rating < 4.7) {
          accepted = false;
        }
        if (filter === '近地铁' && product.distance.indexOf('地铁') < 0 && product.distance.indexOf('步行') < 0) {
          accepted = false;
        }
        if (filter === '直达' && product.stopInfo.indexOf('直达') < 0 && product.stopInfo.indexOf('直飞') < 0) {
          accepted = false;
        }
      }
      if (accepted) {
        filtered.push(product);
      }
    }
    for (let i = 0; i < filtered.length; i++) {
      for (let j = i + 1; j < filtered.length; j++) {
        let shouldSwap: boolean = false;
        if (this.selectedSort === '价格最低' && filtered[i].price > filtered[j].price) {
          shouldSwap = true;
        }
        if (this.selectedSort === '评分优先' && filtered[i].rating < filtered[j].rating) {
          shouldSwap = true;
        }
        if (this.selectedSort === '出发更早' && filtered[i].timelineStart > filtered[j].timelineStart) {
          shouldSwap = true;
        }
        if (shouldSwap) {
          const temp: TravelProduct = filtered[i];
          filtered[i] = filtered[j];
          filtered[j] = temp;
        }
      }
    }
    return filtered;
  }

  private getDisplaySearchSummary(): string {
    if (this.currentService === 'hotel') {
      return `${this.searchForm.toCity} · ${this.searchForm.checkInDate}入住 · ${this.searchForm.checkOutDate}离店 · ${this.searchForm.rooms}间${this.searchForm.travelers}人`;
    }
    if (this.currentService === 'ticket' || this.currentService === 'vacation') {
      return `${this.searchForm.toCity} · ${this.searchForm.departDate}出发 · ${this.searchForm.travelers}人`;
    }
    return `${this.searchForm.fromCity} → ${this.searchForm.toCity} · ${this.searchForm.departDate}出发 · ${this.searchForm.travelers}人`;
  }

  private getTravelDateText(): string {
    return this.currentService === 'hotel' ? `${this.searchForm.checkInDate} 入住` : `${this.searchForm.departDate} 出行`;
  }

  private getFinalAmount(): number {
    const pkg: TravelPackage | undefined = this.getSelectedPackage();
    if (pkg === undefined) {
      return 0;
    }
    return this.currentService === 'hotel' ? pkg.price * 2 : pkg.price * this.searchForm.travelers;
  }

  @Builder
  private buildHeader(title: string, subtitle: string, showBack: boolean = false) {
    Row() {
      if (showBack) {
        Button('<')
          .width(32)
          .height(32)
          .fontSize(16)
          .fontColor('#12325B')
          .backgroundColor('#E8F1FF')
          .margin({ right: 12 })
          .onClick(() => {
            if (this.currentScreen === 'search' || this.currentScreen === 'orders' || this.currentScreen === 'service' || this.currentScreen === 'profile') {
              this.goTab(0);
            } else if (this.currentScreen === 'results') {
              this.currentScreen = 'search';
            } else if (this.currentScreen === 'detail') {
              this.currentScreen = 'results';
            } else if (this.currentScreen === 'booking') {
              this.currentScreen = 'detail';
            } else if (this.currentScreen === 'payment') {
              this.currentScreen = 'booking';
            } else if (this.currentScreen === 'orderDetail') {
              this.currentScreen = 'orders';
            }
          })
      }
      Column({ space: 4 }) {
        Text(title)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#102A43')
        Text(subtitle)
          .fontSize(13)
          .fontColor('#5F728C')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('安心出行')
        .fontSize(12)
        .fontColor('#0A5EFF')
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor('#EAF2FF')
        .borderRadius(14)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 18, bottom: 14 })
  }

  @Builder
  private buildServiceTabs() {
    Row() {
      ForEach(homeQuickEntries, (entry: HomeQuickEntry) => {
        Column({ space: 6 }) {
          Text(entry.label)
            .fontSize(16)
            .fontWeight(this.currentService === entry.serviceType ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(this.currentService === entry.serviceType ? '#0A5EFF' : '#556987')
          if (this.currentService === entry.serviceType) {
            Column().width(20).height(3).backgroundColor('#0A5EFF').borderRadius(2)
          } else {
            Blank().height(3)
          }
        }
        .layoutWeight(1)
        .onClick(() => {
          this.applyServiceToForm(entry.serviceType);
        })
      }, (entry: HomeQuickEntry) => entry.id)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 4 })
  }

  @Builder
  private buildDestinationSection(title: string, subtitle: string, items: DestinationCard[]) {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text(title).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#102A43')
          Text(subtitle).fontSize(12).fontColor('#7B8794')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('更多').fontSize(12).fontColor('#0A5EFF')
      }
      .width('100%')

      ForEach(items, (item: DestinationCard) => {
        Row() {
          Column().width(72).height(72).borderRadius(18).backgroundColor('#D9E8FF')
          Column({ space: 6 }) {
            Text(item.city).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#102A43')
            Text(item.description).fontSize(13).fontColor('#5F728C').maxLines(2)
            Text(item.priceHint).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#E85D04')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 14 })
        }
        .width('100%')
        .padding(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(22)
      }, (item: DestinationCard) => item.id)
    }
    .width('100%')
    .margin({ left: 16, right: 16 })
  }

  @Builder
  private buildLabeledField(label: string, value: string) {
    Column({ space: 6 }) {
      Text(label).fontSize(13).fontColor('#7B8794')
      Text(value === '' ? '请选择' : value).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#102A43')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor('#F7FAFC')
    .borderRadius(18)
  }

  @Builder
  private buildPriceRow(label: string, value: string, emphasize: boolean = false) {
    Row() {
      Text(label).fontSize(14).fontColor('#5F728C')
      Blank()
      Text(value)
        .fontSize(emphasize ? 20 : 15)
        .fontWeight(emphasize ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(emphasize ? '#E85D04' : '#102A43')
    }
    .width('100%')
  }

  @Builder
  private buildAssetCard(label: string, value: string) {
    Column({ space: 8 }) {
      Text(value).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#102A43')
      Text(label).fontSize(12).fontColor('#7B8794')
    }
    .layoutWeight(1)
    .padding({ top: 18, bottom: 18 })
    .backgroundColor('#FFFFFF')
    .borderRadius(24)
  }

  @Builder
  private buildTabItem(tabIndex: number, label: string) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(14)
        .fontWeight(this.currentTab === tabIndex ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.currentTab === tabIndex ? '#0A5EFF' : '#6B7C93')
    }
    .layoutWeight(1)
    .onClick(() => {
      this.goTab(tabIndex);
    })
  }

  @Builder
  private buildHomeScreen() {
    Scroll() {
      Column({ space: 18 }) {
        this.buildHeader('途屿旅行', '搜索比价、预订下单、行程服务一站完成')
        this.buildServiceTabs()

        Column({ space: 14 }) {
          Row() {
            Column({ space: 8 }) {
              Text(this.getDisplaySearchSummary()).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#102A43')
              Text('先搜索，再按价格、位置和退改规则做决策').fontSize(13).fontColor('#5F728C')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Button('去查询')
              .height(42)
              .backgroundColor('#0A5EFF')
              .fontColor(Color.White)
              .onClick(() => {
                this.enterSearch(this.currentService);
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .margin({ left: 16, right: 16 })

        GridRow({ columns: 5 }) {
          ForEach(homeQuickEntries, (entry: HomeQuickEntry) => {
            GridCol({ span: 1 }) {
              Column({ space: 10 }) {
                Text(entry.icon)
                  .fontSize(20)
                  .fontColor('#0A5EFF')
                  .width(44)
                  .height(44)
                  .textAlign(TextAlign.Center)
                  .padding({ top: 10 })
                  .backgroundColor('#EAF2FF')
                  .borderRadius(22)
                Text(entry.label).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#243B53')
                Text(entry.hint).fontSize(11).fontColor('#7B8794')
              }
              .width('100%')
              .onClick(() => {
                this.enterSearch(entry.serviceType);
              })
            }
          }, (entry: HomeQuickEntry) => entry.id)
        }
        .margin({ left: 16, right: 16 })

        Scroll() {
          Row({ space: 12 }) {
            ForEach(homeBanners, (banner: BannerItem) => {
              Column({ space: 10 }) {
                Text(banner.title).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                Text(banner.subtitle).fontSize(13).fontColor('#E6F0FF')
              }
              .width(260)
              .height(120)
              .padding(18)
              .backgroundColor(banner.accent)
              .borderRadius(24)
              .alignItems(HorizontalAlign.Start)
            }, (banner: BannerItem) => banner.id)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)

        this.buildDestinationSection('热门目的地', '根据近期浏览为你推荐', popularDestinations)
        this.buildDestinationSection('猜你喜欢', '保留比价与复购路径', personalizedDeals)
        Blank().height(80)
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildSearchScreen() {
    Scroll() {
      Column({ space: 16 }) {
        this.buildHeader(`${this.getCurrentServiceLabel()}搜索`, '结构化录入条件，减少决策成本', true)

        Column({ space: 12 }) {
          this.buildLabeledField(this.currentService === 'hotel' ? '目的地' : '出发地', this.currentService === 'hotel' ? this.searchForm.toCity : this.searchForm.fromCity)
          if (this.currentService !== 'hotel' && this.currentService !== 'ticket' && this.currentService !== 'vacation') {
            this.buildLabeledField('目的地', this.searchForm.toCity)
          }
          if (this.currentService === 'hotel') {
            this.buildLabeledField('入住日期', `${this.searchForm.checkInDate} - ${this.searchForm.checkOutDate}`)
            this.buildLabeledField('房间与住客', `${this.searchForm.rooms} 间 / ${this.searchForm.travelers} 位`)
          } else {
            this.buildLabeledField('出发日期', `${this.searchForm.departDate} - ${this.searchForm.returnDate}`)
            this.buildLabeledField('乘客与偏好', `${this.searchForm.travelers} 位 / ${this.searchForm.cabin}`)
          }
        }
        .width('100%')
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .margin({ left: 16, right: 16 })

        Column({ space: 12 }) {
          Text('常用城市').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#102A43').width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(commonCities, (city: string) => {
              Text(city)
                .fontSize(14)
                .fontColor(city === this.searchForm.toCity || city === this.searchForm.fromCity ? '#0A5EFF' : '#486581')
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .margin({ right: 10, bottom: 10 })
                .backgroundColor(city === this.searchForm.toCity || city === this.searchForm.fromCity ? '#EAF2FF' : '#F5F7FA')
                .borderRadius(18)
                .onClick(() => {
                  if (this.currentService === 'hotel' || this.currentService === 'ticket' || this.currentService === 'vacation') {
                    this.searchForm.toCity = city;
                  } else if (this.searchForm.fromCity === '' || this.searchForm.fromCity === defaultSearchForm.fromCity) {
                    this.searchForm.fromCity = city;
                  } else {
                    this.searchForm.toCity = city;
                  }
                })
            }, (city: string) => city)
          }
        }
        .width('100%')
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .margin({ left: 16, right: 16 })

        Button('查询可订结果')
          .width('90%')
          .height(50)
          .backgroundColor('#0A5EFF')
          .fontColor(Color.White)
          .fontSize(18)
          .onClick(() => {
            this.executeSearch();
          })

        Blank().height(70)
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildResultsScreen() {
    Scroll() {
      Column({ space: 14 }) {
        this.buildHeader(`${this.getCurrentServiceLabel()}结果`, this.getDisplaySearchSummary(), true)

        Scroll() {
          Row({ space: 10 }) {
            ForEach(sortOptions, (option: string) => {
              Text(option)
                .fontSize(14)
                .fontColor(this.selectedSort === option ? '#FFFFFF' : '#486581')
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .backgroundColor(this.selectedSort === option ? '#0A5EFF' : '#FFFFFF')
                .borderRadius(18)
                .onClick(() => {
                  this.selectedSort = option;
                })
            }, (option: string) => option)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(filterOptions, (filter: string) => {
            Text(filter)
              .fontSize(13)
              .fontColor(this.selectedFilters.indexOf(filter) >= 0 ? '#0A5EFF' : '#5F728C')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .margin({ right: 10, bottom: 10 })
              .backgroundColor(this.selectedFilters.indexOf(filter) >= 0 ? '#EAF2FF' : '#FFFFFF')
              .borderRadius(18)
              .onClick(() => {
                this.selectFilter(filter);
              })
          }, (filter: string) => filter)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Text(`共找到 ${this.getProductsByCurrentService().length} 个可订结果`).fontSize(13).fontColor('#7B8794').width('100%').padding({ left: 16, right: 16 })

        ForEach(this.getProductsByCurrentService(), (product: TravelProduct) => {
          Column({ space: 14 }) {
            Row() {
              Column({ space: 6 }) {
                Text(product.cover).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                Text(product.coverSubtext).fontSize(12).fontColor('#DCEBFF').maxLines(2)
              }
              .width(104)
              .height(96)
              .padding(12)
              .backgroundColor('#0A5EFF')
              .borderRadius(20)
              .alignItems(HorizontalAlign.Start)

              Column({ space: 8 }) {
                Text(product.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#102A43').maxLines(1)
                Text(product.subtitle).fontSize(13).fontColor('#5F728C')
                Text(`${product.location} · ${product.distance}`).fontSize(12).fontColor('#7B8794').maxLines(1)
                Text(`${product.timelineStart} - ${product.timelineEnd}  ${product.duration}  ${product.stopInfo}`).fontSize(12).fontColor('#7B8794')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
            }
            .width('100%')

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(product.tags, (tag: string) => {
                Text(tag)
                  .fontSize(11)
                  .fontColor('#0A5EFF')
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .margin({ right: 8, bottom: 8 })
                  .backgroundColor('#EAF2FF')
                  .borderRadius(14)
              }, (tag: string) => tag)
            }

            Row() {
              Column({ space: 4 }) {
                Text(product.policyTag).fontSize(12).fontColor('#E85D04')
                Text(product.inventoryStatus).fontSize(12).fontColor('#D64545')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column({ space: 2 }) {
                Text(`￥${product.price}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#E85D04')
                Text(product.priceLabel).fontSize(12).fontColor('#7B8794')
              }
              .alignItems(HorizontalAlign.End)
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(24)
          .margin({ left: 16, right: 16 })
          .onClick(() => {
            this.openProduct(product.id);
          })
        }, (product: TravelProduct) => product.id)

        Blank().height(80)
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildDetailScreen() {
    if (this.getSelectedProduct() === undefined) {
      Column() {
        Text('未找到商品')
      }
    } else {
      Scroll() {
        Column({ space: 16 }) {
          this.buildHeader(this.getSafeSelectedProduct().title, this.getSafeSelectedProduct().subtitle, true)

          Column({ space: 10 }) {
            Text(this.getSafeSelectedProduct().cover).fontSize(26).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
            Text(this.getSafeSelectedProduct().coverSubtext).fontSize(13).fontColor('#D9E8FF')
          }
          .width('100%')
          .height(180)
          .padding(18)
          .backgroundColor('#0A5EFF')
          .borderRadius(28)
          .margin({ left: 16, right: 16 })
          .alignItems(HorizontalAlign.Start)

          Column({ space: 10 }) {
            Text('核心卖点').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#102A43').width('100%')
            ForEach(this.getSafeSelectedProduct().detailPoints, (point: string) => {
              Text(`• ${point}`).fontSize(14).fontColor('#486581').width('100%')
            }, (point: string) => point)
          }
          .width('100%')
          .padding(18)
          .backgroundColor('#FFFFFF')
          .borderRadius(24)
          .margin({ left: 16, right: 16 })

          Column({ space: 10 }) {
            Text('可订套餐').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#102A43').width('100%')
            ForEach(this.getSafeSelectedProduct().packages, (pkg: TravelPackage) => {
              Column({ space: 10 }) {
                Row() {
                  Column({ space: 4 }) {
                    Text(pkg.name).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#102A43')
                    Text(`${pkg.provider} · ${pkg.policy}`).fontSize(12).fontColor('#5F728C')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text(`￥${pkg.price}/${pkg.unitLabel}`).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#E85D04')
                }
                .width('100%')

                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(pkg.highlights, (tag: string) => {
                    Text(tag)
                      .fontSize(11)
                      .fontColor('#0A5EFF')
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .margin({ right: 8, bottom: 8 })
                      .backgroundColor('#EAF2FF')
                      .borderRadius(14)
                  }, (tag: string) => tag)
                }

                Row() {
                  Text(pkg.inventory).fontSize(12).fontColor('#D64545').layoutWeight(1)
                  Button(this.selectedPackageId === pkg.id ? '已选择' : '选择并预订')
                    .height(38)
                    .backgroundColor(this.selectedPackageId === pkg.id ? '#D9E8FF' : '#0A5EFF')
                    .fontColor(this.selectedPackageId === pkg.id ? '#0A5EFF' : '#FFFFFF')
                    .onClick(() => {
                      this.startBooking(pkg.id);
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#F8FBFF')
              .borderRadius(20)
            }, (pkg: TravelPackage) => pkg.id)
          }
          .width('100%')
          .padding(18)
          .backgroundColor('#FFFFFF')
          .borderRadius(24)
          .margin({ left: 16, right: 16 })

          Blank().height(80)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  private buildBookingScreen() {
    if (this.getSelectedProduct() === undefined || this.getSelectedPackage() === undefined) {
      Column() {
        Text('订单信息缺失')
      }
    } else {
      Scroll() {
        Column({ space: 16 }) {
          this.buildHeader('填写订单', '提交前确认费用构成和退改规则', true)
          Column({ space: 10 }) {
            Text(this.getSafeSelectedProduct().title).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#102A43')
            Text(this.getSafeSelectedPackage().name).fontSize(14).fontColor('#486581')
            Text(`${this.getTravelDateText()} · ${this.getSafeSelectedPackage().policy}`).fontSize(12).fontColor('#7B8794')
          }
          .width('100%')
          .padding(18)
          .backgroundColor('#FFFFFF')
          .borderRadius(24)
          .margin({ left: 16, right: 16 })

          Column({ space: 12 }) {
            this.buildLabeledField('出行人 / 入住人', this.draftTraveler)
            this.buildLabeledField('手机号', this.draftPhone)
            this.buildLabeledField('发票', this.invoiceRequired ? '需要报销发票' : '暂不需要')
          }
          .width('100%')
          .padding(18)
          .backgroundColor('#FFFFFF')
          .borderRadius(24)
          .margin({ left: 16, right: 16 })

          Column({ space: 10 }) {
            Text('费用明细').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#102A43').width('100%')
            this.buildPriceRow('套餐价格', `￥${this.getSafeSelectedPackage().price}`)
            this.buildPriceRow(this.currentService === 'hotel' ? '间夜数' : '出行人数', this.currentService === 'hotel' ? '2 晚' : `${this.searchForm.travelers} 人`)
            this.buildPriceRow('服务保障', '含')
            this.buildPriceRow('总价', `￥${this.getFinalAmount()}`, true)
          }
          .width('100%')
          .padding(18)
          .backgroundColor('#FFFFFF')
          .borderRadius(24)
          .margin({ left: 16, right: 16 })

          Button('提交订单').width('90%').height(50).backgroundColor('#0A5EFF').fontColor(Color.White).fontSize(18).onClick(() => {
            this.submitBooking();
          })
          Blank().height(70)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  private buildPaymentScreen() {
    Scroll() {
      Column({ space: 16 }) {
        this.buildHeader('支付确认', '倒计时内完成支付可锁定价格和库存', true)
        Column({ space: 12 }) {
          Text(`￥${this.getFinalAmount()}`).fontSize(34).fontWeight(FontWeight.Bold).fontColor('#E85D04')
          Text(`剩余支付时间 ${this.paymentCountdown}:00`).fontSize(14).fontColor('#D64545')
        }
        .width('100%')
        .padding(24)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .margin({ left: 16, right: 16 })

        Column({ space: 12 }) {
          ForEach(['微信支付', '支付宝', '银行卡'], (method: string) => {
            Row() {
              Text(method).fontSize(16).fontColor('#102A43')
              Blank()
              Text(this.paymentMethod === method ? '已选' : '选择').fontSize(13).fontColor(this.paymentMethod === method ? '#0A5EFF' : '#7B8794')
            }
            .width('100%')
            .padding(14)
            .backgroundColor('#F7FAFC')
            .borderRadius(18)
            .onClick(() => {
              this.paymentMethod = method;
            })
          }, (method: string) => method)
        }
        .width('100%')
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .margin({ left: 16, right: 16 })

        Button('确认支付').width('90%').height(50).backgroundColor('#0A5EFF').fontColor(Color.White).fontSize(18).onClick(() => {
          this.completePayment();
        })
        Blank().height(70)
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildOrdersScreen() {
    Scroll() {
      Column({ space: 14 }) {
        this.buildHeader('订单与行程', '支付后订单、提醒和售后入口统一收口', this.currentTab !== 1)
        ForEach(this.orders, (order: OrderCard) => {
          Column({ space: 10 }) {
            Row() {
              Column({ space: 4 }) {
                Text(order.title).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#102A43')
                Text(order.subtitle).fontSize(13).fontColor('#5F728C')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(order.status).fontSize(12).fontColor('#0A5EFF').padding({ left: 10, right: 10, top: 6, bottom: 6 }).backgroundColor('#EAF2FF').borderRadius(14)
            }
            .width('100%')

            Text(order.travelDate).fontSize(13).fontColor('#486581').width('100%')
            Text(order.reminder).fontSize(12).fontColor('#7B8794').width('100%')
            Row() {
              Text(`￥${order.amount}`).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#E85D04')
              Blank()
              Button(order.actionLabel).height(36).backgroundColor('#0A5EFF').fontColor(Color.White).onClick(() => {
                this.selectOrder(order.id);
              })
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(24)
          .margin({ left: 16, right: 16 })
        }, (order: OrderCard) => order.id)
        Blank().height(80)
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildOrderDetailScreen() {
    if (this.getSelectedOrder() === undefined) {
      Column() {
        Text('订单不存在')
      }
    } else {
      Scroll() {
        Column({ space: 16 }) {
          this.buildHeader('订单详情', '查看出行提醒、售后和复购入口', true)
          Column({ space: 10 }) {
            Text(this.getSafeSelectedOrder().title).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#102A43')
            Text(this.getSafeSelectedOrder().subtitle).fontSize(14).fontColor('#486581')
            Text(this.getSafeSelectedOrder().travelDate).fontSize(13).fontColor('#7B8794')
            Text(this.getSafeSelectedOrder().reminder).fontSize(13).fontColor('#D64545')
          }
          .width('100%')
          .padding(18)
          .backgroundColor('#FFFFFF')
          .borderRadius(24)
          .margin({ left: 16, right: 16 })

          Column({ space: 12 }) {
            this.buildLabeledField('订单状态', this.getSafeSelectedOrder().status)
            this.buildLabeledField('订单金额', `￥${this.getSafeSelectedOrder().amount}`)
            this.buildLabeledField('售后服务', '改签 / 取消 / 联系客服')
          }
          .width('100%')
          .padding(18)
          .backgroundColor('#FFFFFF')
          .borderRadius(24)
          .margin({ left: 16, right: 16 })
          Blank().height(70)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  private buildServiceScreen() {
    Scroll() {
      Column({ space: 16 }) {
        this.buildHeader('客服与消息', '让售后和行程提醒保持高可发现性', this.currentTab !== 2)
        Column({ space: 12 }) {
          this.buildLabeledField('智能客服', '退改签、发票、行程变更一键咨询')
          this.buildLabeledField('出行提醒', '航班变动、酒店入住、门票预约及时通知')
          this.buildLabeledField('服务承诺', '价格透明、库存提醒、支付状态实时反馈')
        }
        .width('100%')
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .margin({ left: 16, right: 16 })
        Blank().height(70)
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildProfileScreen() {
    Scroll() {
      Column({ space: 16 }) {
        this.buildHeader('我的', '会员资产、常用信息和订单入口集中管理', this.currentTab !== 3)
        Column({ space: 10 }) {
          Text(memberProfileMock.name).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#102A43')
          Text(memberProfileMock.level).fontSize(13).fontColor('#0A5EFF')
        }
        .width('100%')
        .padding(20)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .margin({ left: 16, right: 16 })
        .alignItems(HorizontalAlign.Start)

        Row() {
          this.buildAssetCard('积分', `${memberProfileMock.points}`)
          this.buildAssetCard('钱包', `￥${memberProfileMock.wallet}`)
          this.buildAssetCard('优惠券', `${memberProfileMock.coupons}张`)
        }
        .width('100%')
        .margin({ left: 16, right: 16 })

        Column({ space: 12 }) {
          this.buildLabeledField('常用旅客', '2 位已实名，支持快速复购')
          this.buildLabeledField('发票与报销', '统一查看已开票记录')
          this.buildLabeledField('设置', '通知、隐私、账号安全')
        }
        .width('100%')
        .padding(18)
        .backgroundColor('#FFFFFF')
        .borderRadius(24)
        .margin({ left: 16, right: 16 })
        Blank().height(70)
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildBottomTabs() {
    Row() {
      this.buildTabItem(0, '首页')
      this.buildTabItem(1, '订单')
      this.buildTabItem(2, '客服')
      this.buildTabItem(3, '我的')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 14 })
    .backgroundColor('#FFFFFF')
    .borderRadius({ topLeft: 24, topRight: 24 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.currentScreen === 'home') {
          this.buildHomeScreen()
        } else if (this.currentScreen === 'search') {
          this.buildSearchScreen()
        } else if (this.currentScreen === 'results') {
          this.buildResultsScreen()
        } else if (this.currentScreen === 'detail') {
          this.buildDetailScreen()
        } else if (this.currentScreen === 'booking') {
          this.buildBookingScreen()
        } else if (this.currentScreen === 'payment') {
          this.buildPaymentScreen()
        } else if (this.currentScreen === 'orders') {
          this.buildOrdersScreen()
        } else if (this.currentScreen === 'service') {
          this.buildServiceScreen()
        } else if (this.currentScreen === 'profile') {
          this.buildProfileScreen()
        } else {
          this.buildOrderDetailScreen()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F3F7FB')

      if (this.currentScreen === 'home' || this.currentScreen === 'orders' || this.currentScreen === 'service' || this.currentScreen === 'profile') {
        this.buildBottomTabs()
      }
    }
    .width('100%')
    .height('100%')
  }
}
