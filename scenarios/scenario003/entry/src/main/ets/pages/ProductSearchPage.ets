import router from '@ohos.router';
import { ProductItem } from '../common/model/ProductItem';
import { productsMock } from '../common/mock/productsMock';

@Entry
@Component
struct ProductSearchPage {
  @State selectedCategory: string = '全部';
  @State sortBy: string = '综合';
  @State products: ProductItem[] = [];
  @State filteredProducts: ProductItem[] = [];

  categories: string[] = ['全部', '图书', '数码', '服装', '食品'];
  sortOptions: string[] = ['综合', '销量', '价格升序', '价格降序'];

  aboutToAppear(): void {
    this.products = productsMock;
    this.filteredProducts = productsMock;
  }

  build() {
    Column() {
      // 搜索栏
      Row() {
        TextInput({ placeholder: '搜索商品', text: '' })
          .width('70%')
          .height(40)
          .backgroundColor('#F0F0F0')
          .borderRadius(20)
          .padding({ left: 15, right: 15 })

        Button('搜索')
          .width('25%')
          .height(40)
          .backgroundColor('#0A59F7')
          .fontColor('#FFFFFF')
          .borderRadius(20)
      }
      .width('100%')
      .padding(15)
      .backgroundColor(Color.White)

      // 分类导航栏
      Column() {
        Row() {
          ForEach(this.categories, (category: string, index: number) => {
            Button(category)
              .width('60px')
              .height(40)
              .fontSize(14)
              .fontWeight(index === this.categories.indexOf(this.selectedCategory) ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(index === this.categories.indexOf(this.selectedCategory) ? '#0A59F7' : '#808080')
              .backgroundColor(index === this.categories.indexOf(this.selectedCategory) ? '#E8F3FF' : '#FFFFFF')
              .borderRadius(20)
              .onClick(() => {
                this.selectedCategory = category;
                this.applyFilter();
              })
          }, (category: string) => category)
        }
        .width('100%')
        .padding({ bottom: 10 })
      }
      .width('100%')
      .padding({ left: 15, right: 15, top: 10 })
      .backgroundColor('#F5F5F5')

      // 排序导航栏
      Column() {
        Row() {
          ForEach(this.sortOptions, (option: string, index: number) => {
            Button(option)
              .width('80px')
              .height(35)
              .fontSize(13)
              .fontWeight(index === this.sortOptions.indexOf(this.sortBy) ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(index === this.sortOptions.indexOf(this.sortBy) ? '#0A59F7' : '#808080')
              .backgroundColor(index === this.sortOptions.indexOf(this.sortBy) ? '#E8F3FF' : '#FFFFFF')
              .borderRadius(18)
              .onClick(() => {
                this.sortBy = option;
                this.applySort();
              })
          }, (option: string) => option)
        }
        .width('100%')
        .padding({ top: 5, bottom: 10 })
      }
      .width('100%')
      .padding({ left: 15, right: 15 })
      .backgroundColor(Color.White)

      // 商品列表
      List() {
        ForEach(this.filteredProducts, (product: ProductItem, index: number) => {
          ListItem() {
            Row() {
              Row() {
                Column({ space: 8 }) {
                  Image('')
                    .width('120px')
                    .height('120px')
                    .backgroundColor('#E8E8E8')
                    .borderRadius(10)

                  Text(`${product.name.substring(0, 6)}...`)
                    .fontSize(12)
                    .fontColor('#808080')
                }
                .width('120px')
                .height('180px')
                .alignItems(HorizontalAlign.Center)
              }

              Column({ space: 5 }) {
                Text(product.name)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#000000')
                  .layoutWeight(1)
                  .maxLines(2)

                Text('￥' + product.price.toFixed(2))
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FF4400')

                Text(`销量 ${product.sales}`)
                  .fontSize(12)
                  .fontColor('#808080')
              }
              .width('160px')
              .padding({ left: 10 })
            }
            .width('100%')
            .padding(12)
            .backgroundColor(Color.White)
            .borderRadius(12)
          }
        }, (product: ProductItem) => product.id)
      }
      .width('100%')
      .padding(15)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8F8')
  }

  private applyFilter(): void {
    if (this.selectedCategory === '全部') {
      this.filteredProducts = this.products;
    } else {
      this.filteredProducts = this.products.filter(p => p.category === this.selectedCategory);
    }
    this.applySort();
  }

  private applySort(): void {
    switch (this.sortBy) {
      case '综合':
        break;
      case '销量':
        this.filteredProducts.sort((a: ProductItem, b: ProductItem) => b.sales - a.sales);
        break;
      case '价格升序':
        this.filteredProducts.sort((a: ProductItem, b: ProductItem) => a.price - b.price);
        break;
      case '价格降序':
        this.filteredProducts.sort((a: ProductItem, b: ProductItem) => b.price - a.price);
        break;
    }
  }
}
