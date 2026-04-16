export interface MessageItem {
  id: string;
  category: string;
  userName: string;
  avatar: string;
  content: string;
  time: string;
  unread: boolean;
}

const MESSAGE_ITEMS: MessageItem[] = [
  { id: 'message-001', category: '互动消息', userName: '北川', avatar: 'BC', content: '点赞了你的内容《晨间工作台公开》', time: '刚刚', unread: true },
  { id: 'message-002', category: '评论回复', userName: 'Mina', avatar: 'MN', content: '回复：这个封面比例太实用了', time: '9 分钟前', unread: true },
  { id: 'message-003', category: '新增粉丝', userName: '阿哲', avatar: 'AZ', content: '关注了你，并收藏了 2 条内容', time: '24 分钟前', unread: false },
  { id: 'message-004', category: '系统通知', userName: '内容助手', avatar: 'SYS', content: '你的草稿已自动保存，可继续编辑发布。', time: '1 小时前', unread: false }
];

export function cloneMessagesMock(): MessageItem[] {
  return MESSAGE_ITEMS.map((item: MessageItem) => {
    const clonedItem: MessageItem = {
      id: item.id,
      category: item.category,
      userName: item.userName,
      avatar: item.avatar,
      content: item.content,
      time: item.time,
      unread: item.unread
    };
    return clonedItem;
  });
}
