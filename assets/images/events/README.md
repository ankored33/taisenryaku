# イベント画像ディレクトリ構成

イベント画像は `res://assets/images/events/` 配下に配置します。

## 構成

- `common/`: 複数ステージで使い回す共通画像
- `common/`: 敗北後イベント (`event_after_defeat`) を含む全体共通画像
- `<girl_id>/<stage_id>/before/`: 開始前イベント (`event_before`)
- `<girl_id>/<stage_id>/after_victory/`: 勝利後イベント (`event_after_victory`)

## 例

- `res://assets/images/events/girl_a/girl_a_01/before/cut_01.png`
- `res://assets/images/events/girl_b/girl_b_02/after_victory/cut_02.png`
- `res://assets/images/events/common/after_defeat_main.png`
- `res://assets/images/events/common/system_notice.png`

## 命名ルール

- cut画像は `cut_01.png`, `cut_02.png` のように連番
- 1イベント1枚のみなら `main.png` を推奨
- 画像サイズは用途に応じて可変。横長カットは `1280x720` 基準を推奨
