# 画像アセット配置ルール

今後の画像は `res://assets/images/` 配下に用途別で配置します。

- `events/`: イベントシーンで使う画像
- `units/`: ユニット立ち絵・アイコン
- `backgrounds/`: 汎用背景
- `ui/`: UI用画像

## イベント画像の指定例

ステージ JSON の `event_before` / `event_after_victory` / `event_after_defeat` の `image` には、以下のように `res://` から始まるパスを指定します。

`res://assets/images/events/stage01_briefing.png`

## 方針

画像は `assets/images/` 配下に集約します。
