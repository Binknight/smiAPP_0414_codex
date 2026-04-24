interface TodoItem {
  title: string;
  done: boolean;
}

@Entry
@Component
struct Index {
  @State private clickCount: number = 0;
  @State private todos: TodoItem[] = [
    { title: 'Learn ArkUI declarative layout', done: true },
    { title: 'Add a network request', done: false },
    { title: 'Create page navigation', done: false }
  ];

  private toggleTodo(index: number): void {
    const next: TodoItem[] = [];
    for (let i = 0; i < this.todos.length; i++) {
      const item = this.todos[i];
      next.push({
        title: item.title,
        done: i === index ? !item.done : item.done
      });
    }
    this.todos = next;
  }

  build() {
    Column({ space: 18 }) {
      Column({ space: 10 }) {
        Text('HarmonyOS ArkUI')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#182431')

        Text('A simple home page with state, list rendering, and click interaction.')
          .fontSize(15)
          .fontColor('#4E5969')
          .lineHeight(22)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 12 }) {
        Text(`Button clicked ${this.clickCount} times`)
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')

        Button('Tap Here')
          .type(ButtonType.Capsule)
          .backgroundColor('#0A59F7')
          .fontColor(Color.White)
          .width('100%')
          .height(48)
          .onClick(() => {
            this.clickCount += 1;
          })
      }
      .width('100%')
      .padding(20)
      .backgroundColor('#FFFFFF')
      .borderRadius(24)

      Column({ space: 10 }) {
        Text('Build Checklist')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .textAlign(TextAlign.Start)

        ForEach(this.todos, (item: TodoItem, index: number) => {
          Row() {
            Column()
              .width(18)
              .height(18)
              .borderRadius(9)
              .backgroundColor(item.done ? '#16A34A' : '#D0D7E2')

            Text(item.title)
              .layoutWeight(1)
              .margin({ left: 12 })
              .fontSize(16)
              .fontColor(item.done ? '#60758A' : '#1D2939')
              .decoration({
                type: item.done ? TextDecorationType.LineThrough : TextDecorationType.None
              })

            Button(item.done ? 'Undo' : 'Done')
              .fontSize(14)
              .height(32)
              .backgroundColor(item.done ? '#E5E7EB' : '#DBEAFE')
              .fontColor(item.done ? '#334155' : '#1D4ED8')
              .onClick(() => {
                this.toggleTodo(index);
              })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .backgroundColor('#FFFFFF')
          .borderRadius(18)
        }, (item: TodoItem) => item.title)
      }
      .width('100%')

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .backgroundColor('#F3F6FB')
  }
}
