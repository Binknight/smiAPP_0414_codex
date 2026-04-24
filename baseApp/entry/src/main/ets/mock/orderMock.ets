import { MemberProfile, OrderCard } from '../models/AppModels';

export const orderMockList: OrderCard[] = [
  {
    id: 'order-1001',
    serviceType: 'hotel',
    title: '上海静安云栖酒店',
    subtitle: '高级大床房 / 2 晚',
    amount: 1176,
    status: '待出行',
    travelDate: '04-26 入住',
    actionLabel: '查看订单',
    reminder: '入住前一天 18:00 提醒办理入住'
  },
  {
    id: 'order-1002',
    serviceType: 'flight',
    title: '国航 CA1831',
    subtitle: '北京 → 上海 / 经济舱',
    amount: 760,
    status: '待支付',
    travelDate: '04-26 07:35 起飞',
    actionLabel: '继续支付',
    reminder: '支付剩余 14 分钟，超时将自动取消'
  },
  {
    id: 'order-1003',
    serviceType: 'ticket',
    title: '上海迪士尼乐园门票',
    subtitle: '成人票 x2',
    amount: 798,
    status: '已完成',
    travelDate: '03-28 已使用',
    actionLabel: '再次预订',
    reminder: '可从历史订单快速复购'
  }
];

export const memberProfileMock: MemberProfile = {
  name: '王晨',
  level: '白金会员',
  points: 4860,
  wallet: 320,
  coupons: 8
};
