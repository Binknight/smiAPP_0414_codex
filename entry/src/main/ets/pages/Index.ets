import { cloneDiscoverMock, DiscoverSection, TopicCard } from '../mock/DiscoverMock';
import { cloneFeedMock, ContentItem, MockComment } from '../mock/FeedMock';
import { cloneMessagesMock, MessageItem } from '../mock/MessagesMock';
import { cloneProfileMock, DraftItem, ProfileStat, UserProfile } from '../mock/ProfileMock';
import { cloneSearchSuggestions, cloneSearchTrends, SearchSuggestion, SearchTrend } from '../mock/SearchMock';

interface NavItem {
  id: string;
  label: string;
}

const HOME_CHANNELS: string[] = ['推荐', '关注', '同城', '热榜'];
const PROFILE_TABS: string[] = ['作品', '收藏', '草稿'];
const BOTTOM_NAVS: NavItem[] = [
  { id: 'home', label: '首页' },
  { id: 'discover', label: '发现' },
  { id: 'publish', label: '发布' },
  { id: 'message', label: '消息' },
  { id: 'profile', label: '我的' }
];

function cloneContentItem(item: ContentItem): ContentItem {
  const cloned: ContentItem = {
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
    commentList: item.commentList.map((comment: MockComment) => {
      const clonedComment: MockComment = {
        userName: comment.userName,
        message: comment.message,
        likes: comment.likes
      };
      return clonedComment;
    })
  };
  return cloned;
}

@Entry
@Component
struct Index {
  @State private currentTab: number = 0;
  @State private currentChannel: number = 0;
  @State private profileTab: number = 0;
  @State private searchKeyword: string = '';
  @State private publishTitle: string = '城市内容实验：一条内容从选题到发布';
  @State private publishDescription: string = '保留 mock 工作流，模拟选择素材、补充描述、添加标签与发布四步闭环。';
  @State private publishTag: string = '内容策划';
  @State private feedItems: ContentItem[] = cloneFeedMock();
  @State private discoverSections: DiscoverSection[] = cloneDiscoverMock();
  @State private searchSuggestions: SearchSuggestion[] = cloneSearchSuggestions();
  @State private searchTrends: SearchTrend[] = cloneSearchTrends();
  @State private messageItems: MessageItem[] = cloneMessagesMock();
  @State private profile: UserProfile = cloneProfileMock();
  @State private selectedContentId: string = '';
  @State private toastText: string = '';

  private getVisibleFeedItems(): ContentItem[] {
    const currentChannelName: string = HOME_CHANNELS[this.currentChannel];
    const result: ContentItem[] = [];
    for (let i = 0; i < this.feedItems.length; i++) {
      const item: ContentItem = this.feedItems[i];
      const matchChannel: boolean = currentChannelName === '推荐' ? item.channel === '推荐' || item.channel === '热榜'
        : item.channel === currentChannelName;
      const matchKeyword: boolean = this.searchKeyword.length === 0
        || item.title.indexOf(this.searchKeyword) >= 0
        || item.summary.indexOf(this.searchKeyword) >= 0
        || item.topic.indexOf(this.searchKeyword) >= 0;
      if (matchChannel && matchKeyword) {
        result.push(item);
      }
    }
    return result;
  }

  private getSelectedContent(): ContentItem | null {
    for (let i = 0; i < this.feedItems.length; i++) {
      if (this.feedItems[i].id === this.selectedContentId) {
        return this.feedItems[i];
      }
    }
    return null;
  }

  private getProfileList(): ContentItem[] {
    if (this.profileTab === 0) {
      return this.feedItems.slice(0, 3);
    }
    if (this.profileTab === 1) {
      const result: ContentItem[] = [];
      for (let i = 0; i < this.feedItems.length; i++) {
        if (this.feedItems[i].bookmarked) {
          result.push(this.feedItems[i]);
        }
      }
      return result;
    }
    return [];
  }

  private patchContent(itemId: string, handler: (item: ContentItem) => ContentItem): void {
    const next: ContentItem[] = [];
    for (let i = 0; i < this.feedItems.length; i++) {
      const item: ContentItem = this.feedItems[i];
      next.push(item.id === itemId ? handler(cloneContentItem(item)) : cloneContentItem(item));
    }
    this.feedItems = next;
  }

  private showToast(text: string): void {
    this.toastText = text;
  }

  private toggleLike(itemId: string): void {
    this.patchContent(itemId, (item: ContentItem) => {
      item.liked = !item.liked;
      item.likes = item.liked ? item.likes + 1 : item.likes - 1;
      return item;
    });
    this.showToast('点赞状态已更新');
  }

  private toggleBookmark(itemId: string): void {
    this.patchContent(itemId, (item: ContentItem) => {
      item.bookmarked = !item.bookmarked;
      item.bookmarks = item.bookmarked ? item.bookmarks + 1 : item.bookmarks - 1;
      return item;
    });
    this.showToast('收藏状态已更新');
  }

  private toggleFollow(authorHandle: string): void {
    const next: ContentItem[] = [];
    for (let i = 0; i < this.feedItems.length; i++) {
      const item: ContentItem = cloneContentItem(this.feedItems[i]);
      if (item.authorHandle === authorHandle) {
        item.followed = !item.followed;
      }
      next.push(item);
    }
    this.feedItems = next;
    this.showToast('关注状态已更新');
  }

  private publishContent(): void {
    const newItem: ContentItem = {
      id: `draft-published-${this.feedItems.length + 1}`,
      channel: '推荐',
      title: this.publishTitle,
      summary: this.publishDescription,
      authorName: this.profile.name,
      authorHandle: this.profile.handle,
      authorAvatar: 'YL',
      location: '内容实验室',
      topic: this.publishTag,
      coverColor: '#324A5F',
      coverLabel: 'NEW RELEASE',
      duration: '刚刚',
      isVideo: false,
      liked: false,
      bookmarked: false,
      followed: true,
      likes: 0,
      comments: 0,
      bookmarks: 0,
      views: 32,
      publishedAt: '刚刚',
      tags: [this.publishTag, 'Mock 发布', '仿真流程'],
      commentList: []
    };
    const next: ContentItem[] = [newItem];
    for (let i = 0; i < this.feedItems.length; i++) {
      next.push(cloneContentItem(this.feedItems[i]));
    }
    this.feedItems = next;
    this.currentTab = 0;
    this.currentChannel = 0;
    this.selectedContentId = newItem.id;
    this.showToast('内容已发布到推荐流');
  }

  @Builder
  private pageHeader(title: string, subtitle: string) {
    Column({ space: 6 }) {
      Text(title).fontSize(28).fontWeight(FontWeight.Bold).fontColor('#111827')
      Text(subtitle).fontSize(13).lineHeight(20).fontColor('#667085')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private searchBar() {
    Row({ space: 10 }) {
      TextInput({ placeholder: '搜索话题、作者或内容标题', text: this.searchKeyword })
        .layoutWeight(1).height(44).padding({ left: 16, right: 16 }).borderRadius(18).backgroundColor('#FFFFFF')
        .placeholderColor('#98A2B3').fontSize(14)
        .onChange((value: string) => { this.searchKeyword = value; })
      Button('清空').height(44).fontSize(13).fontColor('#344054').backgroundColor('#E4E7EC')
        .onClick(() => { this.searchKeyword = ''; })
    }
    .width('100%')
  }

  @Builder
  private statPill(label: string, value: string) {
    Row({ space: 6 }) {
      Text(label).fontSize(12).fontColor('#667085')
      Text(value).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#111827')
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 }).backgroundColor('#FFFFFF').borderRadius(14)
  }

  @Builder
  private contentCard(item: ContentItem) {
    Column({ space: 14 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Column({ space: 8 }) {
          Blank()
          Text(item.coverLabel).fontSize(13).fontColor('#F8FAFC').fontWeight(FontWeight.Medium)
          Text(item.isVideo ? `视频 ${item.duration}` : `图文 ${item.duration}`).fontSize(12).fontColor('#E2E8F0')
        }
        .width('100%').height(168).padding(18).alignItems(HorizontalAlign.Start).backgroundColor(item.coverColor).borderRadius(28)
        Text(item.topic).fontSize(11).fontColor('#0F172A').backgroundColor('#F8FAFC').borderRadius(12)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 }).margin({ left: 16, bottom: 16 })
      }
      Column({ space: 10 }) {
        Text(item.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#111827').maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.summary).fontSize(13).lineHeight(20).fontColor('#475467').maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(item.authorAvatar).width(34).height(34).textAlign(TextAlign.Center).fontSize(13).fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF').backgroundColor('#344054').borderRadius(17)
          Column({ space: 2 }) {
            Text(item.authorName).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#111827')
            Text(`${item.location} · ${item.publishedAt}`).fontSize(12).fontColor('#667085')
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 10 })
          Button(item.followed ? '已关注' : '关注').fontSize(12).height(34)
            .fontColor(item.followed ? '#344054' : '#FFFFFF')
            .backgroundColor(item.followed ? '#E5E7EB' : '#1D4ED8')
            .onClick(() => { this.toggleFollow(item.authorHandle); })
        }
        .width('100%')
        Row({ space: 8 }) {
          this.statPill('赞', `${item.likes}`)
          this.statPill('评', `${item.comments}`)
          this.statPill('藏', `${item.bookmarks}`)
        }
      }
      .width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('100%').padding(18).backgroundColor('#F9FAFB').borderRadius(30)
    .onClick(() => { this.selectedContentId = item.id; })
  }

  @Builder
  private homePage() {
    Scroll() {
      Column({ space: 18 }) {
        this.pageHeader('Explore Flow', '内容优先、互动清晰、分发高效的内容消费仿真 APP')
        this.searchBar()
        Row({ space: 10 }) {
          ForEach(HOME_CHANNELS, (channel: string, index: number) => {
            Button(channel).height(36).fontSize(14).fontColor(this.currentChannel === index ? '#FFFFFF' : '#344054')
              .backgroundColor(this.currentChannel === index ? '#1D4ED8' : '#E5E7EB')
              .onClick(() => { this.currentChannel = index; })
          }, (item: string) => item)
        }
        .width('100%')
        ForEach(this.getVisibleFeedItems(), (item: ContentItem) => { this.contentCard(item); }, (item: ContentItem) => item.id)
      }
      .padding({ left: 20, right: 20, top: 20, bottom: 120 }).width('100%')
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  private discoverPage() {
    Scroll() {
      Column({ space: 18 }) {
        this.pageHeader('发现与搜索', '从热点、话题和搜索联想进入主题化分发')
        this.searchBar()
        Column({ space: 10 }) {
          Text('热搜榜').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#111827').width('100%').textAlign(TextAlign.Start)
          ForEach(this.searchTrends, (item: SearchTrend) => {
            Row() {
              Text(`${item.rank}`).width(26).fontSize(16).fontWeight(FontWeight.Bold).fontColor(item.rank <= 3 ? '#1D4ED8' : '#667085')
              Column({ space: 2 }) {
                Text(item.keyword).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#111827')
                Text(`${item.volume} 热度`).fontSize(12).fontColor('#667085')
              }
              .layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button('查看').height(30).fontSize(12).backgroundColor('#EAECF0').fontColor('#344054')
                .onClick(() => { this.searchKeyword = item.keyword; this.currentTab = 0; })
            }
            .padding(14).backgroundColor('#FFFFFF').borderRadius(20).width('100%')
          }, (item: SearchTrend) => item.keyword)
        }
        Column({ space: 10 }) {
          Text('联想搜索').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#111827').width('100%').textAlign(TextAlign.Start)
          ForEach(this.searchSuggestions, (item: SearchSuggestion) => {
            Button(`${item.keyword} · ${item.hint}`).height(34).fontSize(12).backgroundColor('#F2F4F7').fontColor('#1D2939')
              .onClick(() => { this.searchKeyword = item.keyword; this.currentTab = 0; })
          }, (item: SearchSuggestion) => item.id)
        }
        ForEach(this.discoverSections, (section: DiscoverSection) => {
          Column({ space: 12 }) {
            Text(section.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#111827').width('100%').textAlign(TextAlign.Start)
            ForEach(section.items, (item: TopicCard) => {
              Column({ space: 10 }) {
                Column({ space: 8 }) {
                  Text(item.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                  Text(item.subtitle).fontSize(13).lineHeight(19).fontColor('#E2E8F0')
                }
                .width('100%').padding(18).alignItems(HorizontalAlign.Start).backgroundColor(item.color).borderRadius(24)
                Text(item.heat).fontSize(12).fontColor('#475467')
              }
              .width('100%')
            }, (item: TopicCard) => item.id)
          }
          .width('100%').alignItems(HorizontalAlign.Start)
        }, (section: DiscoverSection) => section.title)
      }
      .padding({ left: 20, right: 20, top: 20, bottom: 120 }).width('100%')
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  private publishPage() {
    Scroll() {
      Column({ space: 18 }) {
        this.pageHeader('发布中心', '保留轻量创作闭环：选素材、填信息、加标签、发布')
        Text('步骤 1 / 选择素材').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#111827').width('100%').textAlign(TextAlign.Start)
        Row({ space: 12 }) {
          Column({ space: 6 }) {
            Text('视频草稿').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
            Text('9:16 / 18s').fontSize(12).fontColor('#E2E8F0')
          }
          .width('48%').height(120).padding(16).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.End)
          .backgroundColor('#324A5F').borderRadius(24)
          Column({ space: 6 }) {
            Text('图文素材').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#111827')
            Text('6 张图 / 1 张封面').fontSize(12).fontColor('#475467')
          }
          .width('48%').height(120).padding(16).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.End)
          .backgroundColor('#E4E7EC').borderRadius(24)
        }
        TextInput({ placeholder: '填写标题', text: this.publishTitle }).height(48).padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF').borderRadius(18).onChange((value: string) => { this.publishTitle = value; })
        TextArea({ placeholder: '填写内容描述', text: this.publishDescription }).height(140).padding(16)
          .backgroundColor('#FFFFFF').borderRadius(18).onChange((value: string) => { this.publishDescription = value; })
        TextInput({ placeholder: '添加标签', text: this.publishTag }).height(48).padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF').borderRadius(18).onChange((value: string) => { this.publishTag = value; })
        Row({ space: 10 }) {
          this.statPill('可见范围', '公开')
          this.statPill('评论', '允许')
          this.statPill('同步', '频道精选')
        }
        .width('100%')
        Button('步骤 4 / 发布到推荐流').width('100%').height(50).fontSize(16).fontColor('#FFFFFF').backgroundColor('#1D4ED8')
          .borderRadius(22).onClick(() => { this.publishContent(); })
      }
      .padding({ left: 20, right: 20, top: 20, bottom: 120 }).width('100%')
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  private messagePage() {
    Scroll() {
      Column({ space: 16 }) {
        this.pageHeader('消息中心', '承接点赞、评论、收藏、粉丝和系统通知')
        ForEach(this.messageItems, (item: MessageItem) => {
          Row({ space: 12 }) {
            Text(item.avatar).width(42).height(42).textAlign(TextAlign.Center).fontSize(13).fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF').backgroundColor(item.unread ? '#1D4ED8' : '#667085').borderRadius(21)
            Column({ space: 4 }) {
              Text(item.category).fontSize(12).fontColor('#1D4ED8')
              Text(item.userName).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#111827')
              Text(item.content).fontSize(13).lineHeight(20).fontColor('#475467')
              Text(item.time).fontSize(12).fontColor('#98A2B3')
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
          }
          .width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(24)
        }, (item: MessageItem) => item.id)
      }
      .padding({ left: 20, right: 20, top: 20, bottom: 120 }).width('100%')
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  private profilePage() {
    Scroll() {
      Column({ space: 18 }) {
        this.pageHeader('个人主页', '沉淀创作身份、作品资产和草稿状态')
        Column({ space: 14 }) {
          Row({ space: 12 }) {
            Text('YL').width(54).height(54).textAlign(TextAlign.Center).fontSize(18).fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF').backgroundColor('#1F2937').borderRadius(27)
            Column({ space: 4 }) {
              Text(this.profile.name).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#111827')
              Text(`${this.profile.handle} · ${this.profile.location}`).fontSize(13).fontColor('#667085')
              Text(this.profile.bio).fontSize(13).lineHeight(20).fontColor('#475467')
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          Row({ space: 12 }) {
            ForEach(this.profile.stats, (item: ProfileStat) => {
              Column({ space: 4 }) {
                Text(item.value).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#111827')
                Text(item.label).fontSize(12).fontColor('#667085')
              }
              .width('31%').padding(14).backgroundColor('#FFFFFF').borderRadius(20)
            }, (item: ProfileStat) => item.label)
          }
          .width('100%')
        }
        .width('100%')
        Row({ space: 10 }) {
          ForEach(PROFILE_TABS, (tab: string, index: number) => {
            Button(tab).height(34).fontSize(13).fontColor(this.profileTab === index ? '#FFFFFF' : '#344054')
              .backgroundColor(this.profileTab === index ? '#111827' : '#EAECF0')
              .onClick(() => { this.profileTab = index; })
          }, (item: string) => item)
        }
        .width('100%')
        if (this.profileTab < 2) {
          ForEach(this.getProfileList(), (item: ContentItem) => { this.contentCard(item); }, (item: ContentItem) => item.id)
        } else {
          ForEach(this.profile.draftItems, (item: DraftItem) => {
            Row() {
              Column({ space: 4 }) {
                Text(item.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#111827')
                Text(item.step).fontSize(12).fontColor('#667085')
              }
              .layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button('继续编辑').height(32).fontSize(12).fontColor('#FFFFFF').backgroundColor('#1D4ED8')
                .onClick(() => { this.currentTab = 2; this.publishTitle = item.title; })
            }
            .width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(22)
          }, (item: DraftItem) => item.id)
        }
      }
      .padding({ left: 20, right: 20, top: 20, bottom: 120 }).width('100%')
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  private bottomNav() {
    Row() {
      ForEach(BOTTOM_NAVS, (item: NavItem, index: number) => {
        Column() {
          Text(item.label).fontSize(13).fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.currentTab === index ? '#FFFFFF' : '#344054')
        }
        .layoutWeight(1).height(54).justifyContent(FlexAlign.Center).backgroundColor(this.currentTab === index ? '#111827' : '#FFFFFF')
        .borderRadius(18).onClick(() => { this.currentTab = index; })
      }, (item: NavItem) => item.id)
    }
    .width('100%').padding(10).backgroundColor('#F2F4F7').borderRadius(26).margin({ left: 16, right: 16, bottom: 20 })
  }

  @Builder
  private detailPanel(item: ContentItem) {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          Stack({ alignContent: Alignment.BottomStart }) {
            Column({ space: 10 }) {
              Blank()
              Text(item.coverLabel).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
              Text(item.isVideo ? `沉浸式视频 · ${item.duration}` : `图文合集 · ${item.duration}`).fontSize(12).fontColor('#E2E8F0')
            }
            .width('100%').height(240).padding(20).alignItems(HorizontalAlign.Start).backgroundColor(item.coverColor).borderRadius(30)
            Text(item.topic).fontSize(12).fontColor('#111827').backgroundColor('#FFFFFF').borderRadius(12)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 }).margin({ left: 18, bottom: 18 })
          }
          Text(item.title).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#111827')
          Text(item.summary).fontSize(14).lineHeight(22).fontColor('#475467')
          Row({ space: 10 }) {
            Button(item.liked ? `已赞 ${item.likes}` : `点赞 ${item.likes}`).height(40).fontSize(13)
              .fontColor(item.liked ? '#FFFFFF' : '#344054').backgroundColor(item.liked ? '#F04438' : '#EAECF0')
              .onClick(() => { this.toggleLike(item.id); })
            Button(item.bookmarked ? `已收藏 ${item.bookmarks}` : `收藏 ${item.bookmarks}`).height(40).fontSize(13)
              .fontColor(item.bookmarked ? '#FFFFFF' : '#344054').backgroundColor(item.bookmarked ? '#111827' : '#EAECF0')
              .onClick(() => { this.toggleBookmark(item.id); })
          }
          .width('100%')
          ForEach(item.commentList, (comment: MockComment) => {
            Column({ space: 6 }) {
              Text(`${comment.userName} · 赞 ${comment.likes}`).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#111827')
              Text(comment.message).fontSize(13).lineHeight(20).fontColor('#475467')
            }
            .width('100%').padding(14).backgroundColor('#FFFFFF').borderRadius(20)
          }, (comment: MockComment) => `${comment.userName}-${comment.message}`)
        }
        .padding({ left: 20, right: 20, top: 20, bottom: 40 }).width('100%')
      }
      .scrollBar(BarState.Off)
    }
    .width('100%').height('86%').backgroundColor('#F9FAFB').borderRadius({ topLeft: 32, topRight: 32 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.currentTab === 0) {
          this.homePage()
        } else if (this.currentTab === 1) {
          this.discoverPage()
        } else if (this.currentTab === 2) {
          this.publishPage()
        } else if (this.currentTab === 3) {
          this.messagePage()
        } else {
          this.profilePage()
        }
      }
      .width('100%').height('100%').backgroundColor('#F4F6F8')

      this.bottomNav()

      if (this.selectedContentId.length > 0 && this.getSelectedContent() !== null) {
        Column() { Blank() }
          .width('100%').height('100%').backgroundColor('#33000000')
          .onClick(() => { this.selectedContentId = ''; })
        this.detailPanel(this.getSelectedContent() as ContentItem)
        Button('关闭').position({ top: 24, right: 20 }).height(34).fontSize(12).fontColor('#111827').backgroundColor('#FFFFFF')
          .onClick(() => { this.selectedContentId = ''; })
      }

      if (this.toastText.length > 0) {
        Text(this.toastText).fontSize(12).fontColor('#FFFFFF').backgroundColor('#111827').borderRadius(16)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 }).margin({ bottom: 96 })
      }
    }
    .width('100%').height('100%')
  }
}
