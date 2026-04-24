export interface SearchSuggestion {
  id: string;
  keyword: string;
  hint: string;
}

export interface SearchTrend {
  rank: number;
  keyword: string;
  volume: string;
}

const SEARCH_SUGGESTIONS: SearchSuggestion[] = [
  { id: 'search-001', keyword: '城市漫游', hint: '视频 1.2w' },
  { id: 'search-002', keyword: '小空间改造', hint: '图文 8.6k' },
  { id: 'search-003', keyword: '创作者工作流', hint: '合集 5.1k' },
  { id: 'search-004', keyword: '早餐摊记录', hint: '同城热议' }
];

const SEARCH_TRENDS: SearchTrend[] = [
  { rank: 1, keyword: '夜色街拍模板', volume: '295.8w' },
  { rank: 2, keyword: '图文封面排版', volume: '188.4w' },
  { rank: 3, keyword: '阳台阅读角', volume: '176.2w' },
  { rank: 4, keyword: '通勤短片剪辑', volume: '155.9w' },
  { rank: 5, keyword: '社区放映会', volume: '120.3w' }
];

export function cloneSearchSuggestions(): SearchSuggestion[] {
  return SEARCH_SUGGESTIONS.map((item: SearchSuggestion) => {
    const clonedItem: SearchSuggestion = {
      id: item.id,
      keyword: item.keyword,
      hint: item.hint
    };
    return clonedItem;
  });
}

export function cloneSearchTrends(): SearchTrend[] {
  return SEARCH_TRENDS.map((item: SearchTrend) => {
    const clonedItem: SearchTrend = {
      rank: item.rank,
      keyword: item.keyword,
      volume: item.volume
    };
    return clonedItem;
  });
}
