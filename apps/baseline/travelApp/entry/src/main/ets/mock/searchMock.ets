import { SearchFormData, ServiceLabelMap } from '../models/AppModels';

export const serviceLabels: ServiceLabelMap = {
  hotel: '酒店',
  flight: '机票',
  train: '火车票',
  ticket: '门票',
  vacation: '度假'
};

export const sortOptions: string[] = ['推荐优先', '价格最低', '评分优先', '出发更早'];

export const filterOptions: string[] = ['可取消', '含早餐', '高评分', '近地铁', '直达', '限时优惠'];

export const commonCities: string[] = ['北京', '上海', '广州', '深圳', '杭州', '成都', '重庆', '西安'];

export const defaultSearchForm: SearchFormData = {
  serviceType: 'hotel',
  fromCity: '北京',
  toCity: '上海',
  departDate: '04-26',
  returnDate: '04-29',
  checkInDate: '04-26',
  checkOutDate: '04-28',
  travelers: 2,
  rooms: 1,
  cabin: '经济/二等/舒适型'
};
