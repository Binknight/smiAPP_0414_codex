import { BannerItem, DestinationCard, HomeQuickEntry } from '../models/AppModels';

export const homeQuickEntries: HomeQuickEntry[] = [
  { id: 'hotel', label: '酒店', serviceType: 'hotel', hint: '今晚可订', icon: '住' },
  { id: 'flight', label: '机票', serviceType: 'flight', hint: '低价比价', icon: '飞' },
  { id: 'train', label: '火车票', serviceType: 'train', hint: '准点出发', icon: '行' },
  { id: 'ticket', label: '门票', serviceType: 'ticket', hint: '随买随用', icon: '玩' },
  { id: 'vacation', label: '度假', serviceType: 'vacation', hint: '省心套餐', icon: '游' }
];

export const homeBanners: BannerItem[] = [
  { id: 'banner-1', title: '五一错峰出行周', subtitle: '酒店机票联订最高减 280', accent: '#0A5EFF' },
  { id: 'banner-2', title: '亲子乐园限时抢', subtitle: '热门景区门票 2 人同行 8 折', accent: '#FF7B1C' }
];

export const popularDestinations: DestinationCard[] = [
  { id: 'dst-1', city: '上海', description: '城市微度假，地标酒店与乐园门票联动', priceHint: '酒店￥488起' },
  { id: 'dst-2', city: '三亚', description: '海景酒店、亲子套餐和接送机服务', priceHint: '机酒￥1680起' },
  { id: 'dst-3', city: '北京', description: '博物馆、演出和高铁联程推荐', priceHint: '高铁￥279起' }
];

export const personalizedDeals: DestinationCard[] = [
  { id: 'deal-1', city: '杭州西湖', description: '湖景房 + 双早 + 夜游船票组合', priceHint: '￥699/晚' },
  { id: 'deal-2', city: '成都熊猫基地', description: '近景区酒店，支持次日免费取消', priceHint: '￥420/晚' },
  { id: 'deal-3', city: '厦门鼓浪屿', description: '海边民宿和帆船体验打包', priceHint: '￥899起' }
];
