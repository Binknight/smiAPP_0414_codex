export interface MockComment {
  userName: string;
  message: string;
  likes: number;
}

export interface ContentItem {
  id: string;
  channel: string;
  title: string;
  summary: string;
  authorName: string;
  authorHandle: string;
  authorAvatar: string;
  location: string;
  topic: string;
  coverColor: string;
  coverLabel: string;
  duration: string;
  isVideo: boolean;
  liked: boolean;
  bookmarked: boolean;
  followed: boolean;
  likes: number;
  comments: number;
  bookmarks: number;
  views: number;
  publishedAt: string;
  tags: string[];
  commentList: MockComment[];
}

const FEED_ITEMS: ContentItem[] = [
  {
    id: 'feed-001',
    channel: '推荐',
    title: '48 小时拍完一条城市漫游短片，我把镜头都藏进了通勤路上',
    summary: '从地铁站到旧书店，再到凌晨营业的热面馆，镜头跟着城市节奏走，成片更像一份会呼吸的生活提案。',
    authorName: '林序',
    authorHandle: '@linxu',
    authorAvatar: 'LX',
    location: '上海 徐汇',
    topic: '城市叙事',
    coverColor: '#243B53',
    coverLabel: 'VLOG / CITY WALK',
    duration: '02:18',
    isVideo: true,
    liked: true,
    bookmarked: false,
    followed: true,
    likes: 12800,
    comments: 486,
    bookmarks: 2140,
    views: 98600,
    publishedAt: '18 分钟前',
    tags: ['通勤拍摄', '城市漫游', '夜色氛围'],
    commentList: [
      { userName: '阿哲', message: '转场的节奏很稳，像看了一次线下展映。', likes: 182 },
      { userName: 'Mina', message: '地铁门开启那一幕很抓人。', likes: 97 }
    ]
  },
  {
    id: 'feed-002',
    channel: '推荐',
    title: '把 6 平米阳台改成晨间阅读角，只用了三个低成本模块',
    summary: '折叠木桌、亚麻坐垫和悬挂绿植，把原本闲置的阳台做成每日可复用的小型内容场景。',
    authorName: '周朵',
    authorHandle: '@zhouduo',
    authorAvatar: 'ZD',
    location: '杭州 拱墅',
    topic: '居家灵感',
    coverColor: '#E6B89C',
    coverLabel: 'HOME SETUP',
    duration: '09 图',
    isVideo: false,
    liked: false,
    bookmarked: true,
    followed: false,
    likes: 5320,
    comments: 206,
    bookmarks: 3611,
    views: 44200,
    publishedAt: '42 分钟前',
    tags: ['阳台改造', '租房布置', '阅读角'],
    commentList: [
      { userName: '方糖', message: '很适合小户型，收藏等周末动手。', likes: 65 },
      { userName: '林川', message: '木色和绿植搭得很舒服。', likes: 41 }
    ]
  },
  {
    id: 'feed-003',
    channel: '关注',
    title: '连续 7 天记录早餐出摊，最有效的是把备料流程写成时间表',
    summary: '从 4:30 起床到 7:30 第一波客流结束，真正节约时间的不是速度，而是提前拆分流程。',
    authorName: '阿浔',
    authorHandle: '@axun',
    authorAvatar: 'AX',
    location: '成都 武侯',
    topic: '小店经营',
    coverColor: '#5A3E36',
    coverLabel: 'DAILY BUSINESS',
    duration: '01:42',
    isVideo: true,
    liked: false,
    bookmarked: false,
    followed: true,
    likes: 7620,
    comments: 332,
    bookmarks: 1196,
    views: 55300,
    publishedAt: '1 小时前',
    tags: ['早餐摊', '经营记录', '效率'],
    commentList: [
      { userName: '舟舟', message: '原来备料顺序对出品速度影响这么大。', likes: 88 },
      { userName: '阿澈', message: '很真实，凌晨的状态完全能感受到。', likes: 54 }
    ]
  },
  {
    id: 'feed-004',
    channel: '同城',
    title: '今晚的社区放映会太值了，露天银幕和旧墙面意外地搭',
    summary: '放映前的暖场歌单、周边摊位和观众自发带来的折叠椅，把活动做出了很强的参与感。',
    authorName: '叶午',
    authorHandle: '@yewu',
    authorAvatar: 'YW',
    location: '北京 东城',
    topic: '周末活动',
    coverColor: '#1F2A44',
    coverLabel: 'LOCAL EVENT',
    duration: '06 图',
    isVideo: false,
    liked: true,
    bookmarked: true,
    followed: false,
    likes: 4380,
    comments: 194,
    bookmarks: 905,
    views: 22100,
    publishedAt: '今天 20:12',
    tags: ['社区活动', '露天电影', '同城'],
    commentList: [
      { userName: 'Kira', message: '这类活动最能提升社区黏性。', likes: 57 },
      { userName: '北斗', message: '想知道下次还有没有类似场次。', likes: 24 }
    ]
  },
  {
    id: 'feed-005',
    channel: '热榜',
    title: '一个人做内容团队的工作台公开，核心不是设备，而是分发节奏',
    summary: '选题池、剪辑模板和固定复盘日，让单人创作者也能稳定维持更新频率。',
    authorName: '简里',
    authorHandle: '@jianli',
    authorAvatar: 'JL',
    location: '深圳 南山',
    topic: '创作者方法',
    coverColor: '#2E5E4E',
    coverLabel: 'CREATOR STACK',
    duration: '03:06',
    isVideo: true,
    liked: false,
    bookmarked: false,
    followed: false,
    likes: 18300,
    comments: 708,
    bookmarks: 4980,
    views: 132400,
    publishedAt: '2 小时前',
    tags: ['内容运营', '创作者', '工作流'],
    commentList: [
      { userName: '阿宋', message: '分发节奏这点比设备清单更有价值。', likes: 144 },
      { userName: '六月', message: '选题池模板想抄作业。', likes: 102 }
    ]
  },
  {
    id: 'feed-006',
    channel: '推荐',
    title: '我把一周收集到的街头招牌做成字体灵感库，出片率高了很多',
    summary: '把拍到的字形按风格分类后，做封面和标题时几乎不会再出现视觉犹豫。',
    authorName: '乔麦',
    authorHandle: '@qiaomai',
    authorAvatar: 'QM',
    location: '广州 天河',
    topic: '视觉采样',
    coverColor: '#B85C38',
    coverLabel: 'TYPE RESEARCH',
    duration: '12 图',
    isVideo: false,
    liked: false,
    bookmarked: false,
    followed: true,
    likes: 6940,
    comments: 263,
    bookmarks: 2106,
    views: 40180,
    publishedAt: '3 小时前',
    tags: ['字体灵感', '街头采样', '封面设计'],
    commentList: [
      { userName: '莫鱼', message: '这种方法对做内容封面太友好了。', likes: 48 },
      { userName: '晨雨', message: '图文创作者真的需要自己的素材库。', likes: 35 }
    ]
  }
];

function cloneComment(item: MockComment): MockComment {
  return {
    userName: item.userName,
    message: item.message,
    likes: item.likes
  };
}

function cloneContent(item: ContentItem): ContentItem {
  return {
    id: item.id,
    channel: item.channel,
    title: item.title,
    summary: item.summary,
    authorName: item.authorName,
    authorHandle: item.authorHandle,
    authorAvatar: item.authorAvatar,
    location: item.location,
    topic: item.topic,
    coverColor: item.coverColor,
    coverLabel: item.coverLabel,
    duration: item.duration,
    isVideo: item.isVideo,
    liked: item.liked,
    bookmarked: item.bookmarked,
    followed: item.followed,
    likes: item.likes,
    comments: item.comments,
    bookmarks: item.bookmarks,
    views: item.views,
    publishedAt: item.publishedAt,
    tags: item.tags.slice(),
    commentList: item.commentList.map((comment: MockComment) => cloneComment(comment))
  };
}

export function cloneFeedMock(): ContentItem[] {
  return FEED_ITEMS.map((item: ContentItem) => cloneContent(item));
}
