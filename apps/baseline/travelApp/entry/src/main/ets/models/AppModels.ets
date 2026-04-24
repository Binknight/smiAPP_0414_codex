export type ServiceType = 'hotel' | 'flight' | 'train' | 'ticket' | 'vacation';

export interface HomeQuickEntry {
  id: string;
  label: string;
  serviceType: ServiceType;
  hint: string;
  icon: string;
}

export interface BannerItem {
  id: string;
  title: string;
  subtitle: string;
  accent: string;
}

export interface DestinationCard {
  id: string;
  city: string;
  description: string;
  priceHint: string;
}

export interface SearchFormData {
  serviceType: ServiceType;
  fromCity: string;
  toCity: string;
  departDate: string;
  returnDate: string;
  checkInDate: string;
  checkOutDate: string;
  travelers: number;
  rooms: number;
  cabin: string;
}

export interface ServiceLabelMap {
  hotel: string;
  flight: string;
  train: string;
  ticket: string;
  vacation: string;
}

export interface TravelPackage {
  id: string;
  name: string;
  price: number;
  unitLabel: string;
  policy: string;
  inventory: string;
  provider: string;
  highlights: string[];
  instantConfirm: boolean;
}

export interface TravelProduct {
  id: string;
  serviceType: ServiceType;
  title: string;
  subtitle: string;
  location: string;
  distance: string;
  rating: number;
  reviewCount: number;
  price: number;
  originalPrice: number;
  priceLabel: string;
  cover: string;
  coverSubtext: string;
  tags: string[];
  policyTag: string;
  inventoryStatus: string;
  timelineStart: string;
  timelineEnd: string;
  duration: string;
  stopInfo: string;
  facilities: string[];
  detailPoints: string[];
  notices: string[];
  packages: TravelPackage[];
}

export interface OrderCard {
  id: string;
  serviceType: ServiceType;
  title: string;
  subtitle: string;
  amount: number;
  status: string;
  travelDate: string;
  actionLabel: string;
  reminder: string;
}

export interface MemberProfile {
  name: string;
  level: string;
  points: number;
  wallet: number;
  coupons: number;
}
