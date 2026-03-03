# Tiled Workflow

マップ編集は `Tiled` のみを使用します。  
Godot 側の自作マップエディタは廃止しました。

## Stage 設定

`data/stages/<stage_id>.json` に `tiled_map` を設定します。

```json
{
  "tiled_map": {
    "path": "res://data/tiled/stage_01.tmj",
    "terrain_layer": "terrain",
    "default_terrain": "plain",
    "gid_terrain": {
      "1": "plain",
      "2": "basin",
      "3": "forest",
      "4": "hill",
      "5": "peak",
      "6": "water",
      "7": "abyss"
    }
  }
}
```

- `path`: Tiled の `.tmj` ファイルパス
- `terrain_layer`: 地形を読むタイルレイヤー名（未指定時 `terrain`）
- `default_terrain`: GID未設定/未マッピング時の地形
- `gid_terrain`: `gid -> 地形タイプ` の対応表

地形タイプ（現行）は以下です。
- `plain`（平地, 移動1）
- `basin`（窪地, 移動1）
- `forest`（森, 移動2）
- `hill`（丘, 移動3）
- `peak`（通行不可）
- `water`（通行不可）
- `abyss`（通行不可）

## 読み込み仕様

- 読み込みタイミング: `GameFlow` のステージロード時
- `tmj` の `width/height` を `map.cols/map.rows` に反映
- `tmj` のカメラ用オブジェクトから `map.camera` を生成（後述）
- 指定レイヤーの GID から `terrain.paint` を生成
- Tiled の回転/反転フラグ付き GID も対応（フラグを除去して判定）

## カメラ初期位置（Tiled オブジェクト）

Tiled で初期カメラ位置にしたい場所へポイントオブジェクトを置きます。

推奨:
- `objectgroup` レイヤー名: `camera_start`
- そのレイヤーにポイントオブジェクトを1つ配置

検出ルール（上から順に最初に見つかったものを採用）:
- レイヤー名が `camera_start` または `camera`
- オブジェクト名が `camera_start` または `camera`
- オブジェクト type が `camera_start` または `camera`
- オブジェクトプロパティ `objective` が `camera_start` または `camera`

ズームは現在 `1.0` 固定です。

## レイヤー名ルール

Tiled 側で使用するレイヤー名は以下のとおりです。

- `spawn_player`: 味方（player）ユニット配置用 `objectgroup`
- `spawn_enemy`: 敵（enemy）ユニット配置用 `objectgroup`
- `goal_transport`: 輸送目標用 `objectgroup`（任意）
- `capture_points`: 占領拠点用 `objectgroup`（任意）
- 地形レイヤー: `stage.json` の `tiled_map.terrain_layer` で指定（未指定時は `terrain`。見つからなければ最初の `tilelayer`）

## ユニット配置ルール（objectgroup: `spawn_player` / `spawn_enemy`）

各オブジェクトは 1 ユニットを表します。  
`unit_id` または `unit_class` のどちらかが必須です。

### オブジェクトのカスタムプロパティ

- `unit_class` (string, 任意): 兵種ID（例: `infantry`, `transport`）
- `unit_id` (string, 任意): ユニットID。未指定時は自動採番
- `unit_name` (string, 任意): 表示名。未指定時はカタログ名を使用
- `ai_group` (string, 任意): 全ステージ共通AIグループ名（例: `default`, `aggressive`, `cautious`）
- `q` (int, 任意): タイルX
- `r` (int, 任意): タイルY

### 座標解決ルール

- `q` と `r` が両方ある場合: `tile = (q, r)` を使用
- それ以外: オブジェクト座標 `x` / `y` からタイル換算

### IDと名前

- `unit_id` 未指定時: `faction_unitClass_連番` 形式で自動採番
- `unit_name` 未指定時: `data/units.json` の `unit_catalog` から補完

### ai_group の解決

- `ai_group` は `data/ai_groups.json` の `groups` キーを参照
- 未指定または未知のグループ名は `default` にフォールバック（警告ログ出力）

`data/units.json` は兵種マスタ (`unit_catalog`) のみを持ち、マップごとのユニット実体は Tiled の spawn から生成されます。

## 輸送目標ルール（任意）

`goal_transport` レイヤー、または `objective=transport_goal` を持つオブジェクトを1つ配置します。

利用プロパティ:
- `enabled` (bool, 任意, 既定 `true`)
- `faction` (string, 任意, 既定 `player`)
- `unit_class` (string, 任意)
- `score` (int, 任意, 既定 `100`)

位置はオブジェクト `x` / `y` から解決します。

## 占領拠点ルール（任意）

`capture_points` レイヤー、または `objective=capture_point` を持つオブジェクトを拠点として読み込みます。

利用プロパティ:
- `owner` (string, 任意, 既定 `neutral`): `player` / `enemy` / `neutral`
- `q` (int, 任意)
- `r` (int, 任意)

任意の `stage.json` 設定:
- `capture_rules.capture_unit_classes` (string配列): 占領可能兵科。未指定時は `["infantry"]`

座標解決:
- `q/r` があればそれを使用
- なければオブジェクト `x/y` からタイル換算

## 制約

- 対応レイヤーは `tilelayer` のみ
- `data` が配列形式のタイルデータのみ対応
- `base64` など圧縮エンコードは未対応
