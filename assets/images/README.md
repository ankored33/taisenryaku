# 画像アセット配置ルール

今後の画像は `res://assets/images/` 配下に用途別で配置します。

- `events/`: イベントシーンで使う画像
- `units/`: ユニット立ち絵・アイコン
- `backgrounds/`: 汎用背景
- `ui/`: UI用画像
- `characters/`: キャラクター立ち絵

## イベント画像の指定例

ステージ JSON の `event_before` / `event_after_victory` / `event_after_defeat` の `image` には、以下のように `res://` から始まるパスを指定します。

`res://assets/images/events/girl_a/girl_a_01/before/cut_01.png`

イベント画像の詳細ルールは以下を参照してください。

`res://assets/images/events/README.md`

## 方針

画像は `assets/images/` 配下に集約します。
