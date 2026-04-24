export interface ProfileStat {
  label: string;
  value: string;
}

export interface DraftItem {
  id: string;
  title: string;
  step: string;
}

export interface UserProfile {
  name: string;
  handle: string;
  bio: string;
  location: string;
  stats: ProfileStat[];
  draftItems: DraftItem[];
}

const PROFILE_DATA: UserProfile = {
  name: '游序实验室',
  handle: '@explore_lab',
  bio: '记录城市灵感、内容结构和轻创作流程，用 mock 数据快速验证内容消费型产品体验。',
  location: '上海 / 远程创作',
  stats: [
    { label: '关注', value: '218' },
    { label: '粉丝', value: '12.8k' },
    { label: '获赞与收藏', value: '96.4k' }
  ],
  draftItems: [
    { id: 'draft-001', title: '周末 citywalk 选题池', step: '待补封面' },
    { id: 'draft-002', title: '内容团队工作台拆解', step: '待发布' },
    { id: 'draft-003', title: '社区活动观察记录', step: '待补标签' }
  ]
};

export function cloneProfileMock(): UserProfile {
  const profile: UserProfile = {
    name: PROFILE_DATA.name,
    handle: PROFILE_DATA.handle,
    bio: PROFILE_DATA.bio,
    location: PROFILE_DATA.location,
    stats: PROFILE_DATA.stats.map((item: ProfileStat) => {
      const clonedStat: ProfileStat = {
        label: item.label,
        value: item.value
      };
      return clonedStat;
    }),
    draftItems: PROFILE_DATA.draftItems.map((item: DraftItem) => {
      const clonedDraft: DraftItem = {
        id: item.id,
        title: item.title,
        step: item.step
      };
      return clonedDraft;
    })
  };
  return profile;
}
