export interface TopicCard {
  id: string;
  title: string;
  subtitle: string;
  heat: string;
  color: string;
}

export interface DiscoverSection {
  title: string;
  items: TopicCard[];
}

const DISCOVER_SECTIONS: DiscoverSection[] = [
  {
    title: '热门话题',
    items: [
      { id: 'topic-001', title: '# 通勤镜头计划', subtitle: '用 15 秒讲完一段路程', heat: '89.2w 讨论', color: '#25364A' },
      { id: 'topic-002', title: '# 小空间改造', subtitle: '低预算也能出氛围感', heat: '64.1w 浏览', color: '#C97B63' },
      { id: 'topic-003', title: '# 一人工作台', subtitle: '效率和审美如何兼顾', heat: '40.8w 参与', color: '#49796B' }
    ]
  },
  {
    title: '编辑精选',
    items: [
      { id: 'pick-001', title: '夜色街拍专场', subtitle: '高反差封面更抓停留', heat: '专题更新', color: '#1B1F3B' },
      { id: 'pick-002', title: '图文种草模板', subtitle: '标题和信息密度平衡', heat: '12 篇新内容', color: '#8D5A4E' },
      { id: 'pick-003', title: '轻创作挑战', subtitle: '连续 5 天发布练习', heat: '正在进行', color: '#446C52' }
    ]
  }
];

export function cloneDiscoverMock(): DiscoverSection[] {
  return DISCOVER_SECTIONS.map((section: DiscoverSection) => {
    const clonedSection: DiscoverSection = {
      title: section.title,
      items: section.items.map((item: TopicCard) => {
        const clonedItem: TopicCard = {
          id: item.id,
          title: item.title,
          subtitle: item.subtitle,
          heat: item.heat,
          color: item.color
        };
        return clonedItem;
      })
    };
    return clonedSection;
  });
}
