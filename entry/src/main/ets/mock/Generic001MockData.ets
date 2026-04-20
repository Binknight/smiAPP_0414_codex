// This file is auto-generated from dev/mock-data/generic-001.
// Do not edit manually.

export const LOCATION_STATUS_JSON: string = String.raw`{
  "pageTitle": "猫眼门票",
  "pageSubtitle": "旅游购票首页",
  "defaultCity": "上海",
  "detectedCity": "杭州",
  "detectedDistrict": "西湖区",
  "locationLabel": "当前位置",
  "syncState": "mismatch",
  "message": "系统已识别到当前位置在杭州，但首页门票内容仍展示上海。",
  "lastUpdated": "2分钟前",
  "switchActionLabel": "切换到当前位置"
}`;

export const CITY_SWITCH_OPTIONS_JSON: string = String.raw`{
  "options": [
    {
      "code": "shanghai",
      "label": "上海",
      "tag": "当前首页"
    },
    {
      "code": "hangzhou",
      "label": "杭州",
      "tag": "当前位置"
    },
    {
      "code": "suzhou",
      "label": "苏州",
      "tag": "周边热门"
    }
  ]
}`;

export const TICKET_FEED_JSON: string = String.raw`{
  "quickActions": [
    "景点门票",
    "演出票",
    "今日可订",
    "亲子玩乐"
  ],
  "hero": {
    "eyebrow": "周末随时出发",
    "headline": "先切换到当前位置，再看更近的好票",
    "subheadline": "当前定位在杭州，切换后将优先展示西湖、灵隐寺等本地票务。"
  },
  "feeds": [
    {
      "city": "上海",
      "summary": "首页仍停留在上海，推荐结果与当前位置不一致。",
      "tickets": [
        {
          "title": "上海迪士尼乐园一日票",
          "area": "浦东新区",
          "priceLabel": "¥475 起",
          "score": "4.8",
          "distance": "距你 176km",
          "highlight": "热门亲子"
        },
        {
          "title": "东方明珠城市观光联票",
          "area": "陆家嘴",
          "priceLabel": "¥199 起",
          "score": "4.6",
          "distance": "距你 171km",
          "highlight": "夜景推荐"
        },
        {
          "title": "上海海昌海洋公园门票",
          "area": "临港新片区",
          "priceLabel": "¥269 起",
          "score": "4.7",
          "distance": "距你 189km",
          "highlight": "当日可订"
        }
      ]
    },
    {
      "city": "杭州",
      "summary": "切换到当前位置后，优先展示离你更近的门票与当日场次。",
      "tickets": [
        {
          "title": "西湖游船日间票",
          "area": "西湖景区",
          "priceLabel": "¥55 起",
          "score": "4.9",
          "distance": "距你 3.2km",
          "highlight": "今日可订"
        },
        {
          "title": "灵隐飞来峰景区门票",
          "area": "灵隐路",
          "priceLabel": "¥45 起",
          "score": "4.8",
          "distance": "距你 6.5km",
          "highlight": "本地热卖"
        },
        {
          "title": "宋城千古情演出票",
          "area": "之江路",
          "priceLabel": "¥320 起",
          "score": "4.7",
          "distance": "距你 11.4km",
          "highlight": "晚场充足"
        }
      ]
    },
    {
      "city": "苏州",
      "summary": "周边热门城市供你参考，适合短途出游。",
      "tickets": [
        {
          "title": "拙政园门票",
          "area": "姑苏区",
          "priceLabel": "¥80 起",
          "score": "4.8",
          "distance": "距你 154km",
          "highlight": "园林经典"
        },
        {
          "title": "苏州博物馆西馆特展票",
          "area": "高新区",
          "priceLabel": "¥68 起",
          "score": "4.7",
          "distance": "距你 162km",
          "highlight": "周末可约"
        },
        {
          "title": "周庄古镇日游票",
          "area": "昆山",
          "priceLabel": "¥95 起",
          "score": "4.6",
          "distance": "距你 168km",
          "highlight": "适合一日游"
        }
      ]
    }
  ]
}`;
