# PicoShop

ゲームアイコン・文字素材などをドット単位で精密に編集するための macOS ネイティブ（SwiftUI）グラフィック編集ツール。

## ビルドと起動

```bash
cd PicoShop
swift build
.build/debug/PicoShop

# 起動時に画像を開く場合
PICOSHOP_OPEN=/path/to/image.png .build/debug/PicoShop
```

要件: macOS 14 以降 / Swift 5.9 以降

## 主な機能

- **レイヤー**: 追加・削除・複製・並び替え・統合、表示/非表示、ロック、合成モード 5 種（標準/乗算/スクリーン/オーバーレイ/加算）、不透明度、オフセット
- **矩形選択**: 数値入力対応、新規/追加/除外モード切替
- **フリーハンド選択**: ポリゴンラッソ、新規/追加/除外モード切替
- **色域選択**: 背景色自動検出・Level・Erosion・内側選択、新規/追加/除外モード切替
- **マスクブラシ**: 選択マスクをブラシで直接描画
- **変形ツール**: 選択範囲内の画像を移動/スケール/回転（ハンドル + 数値入力）
- **編集**: カット（透明化）・塗りつぶし（選択範囲 / フローフィル）・リサイズ（Nearest/Bilinear/Bicubic/Lanczos）・回転・反転
- **テキスト**: フォント/サイズ/太さ/色/アンチエイリアス/配置基準 9 点を指定してラスタライズ
- **キーボード操作**: カーソルキーで 1px 移動、Shift+カーソルキーで 1px サイズ変更（レイヤー/選択モード切替対応）
- **右インスペクタ**: ルーペ・ナビゲーター・レイヤーをメインウィンドウ右側に集約
- **ルーペ**: 拡大率 1×/2×/4×/8×、座標/RGB/Hex 表示、ピクセルグリッド
- **ナビゲーター**: サムネイル + 赤枠ドラッグで表示位置移動
- **ファイル**: `.pic` プロジェクト保存（ZIP + manifest.json、レイヤー情報保持）、PNG/JPEG/TIFF エクスポート、PNG/JPEG/TIFF/BMP 読み込み（ドラッグ&ドロップ対応）
- **アンドゥ/リドゥ**: 直近 50 操作（操作名つき）

## 構成

```
Sources/PicoShop/
├─ PicoShopApp.swift        # エントリポイント・メニュー定義
├─ Engine/                  # UI 非依存のピクセル処理
│   ├─ PixelBuffer.swift    # RGBA8 バッファ（sRGB / unpremultiplied）
│   ├─ SelectionMask.swift  # 選択マスク（union/subtracting・変形・拡縮・境界パス）
│   ├─ ColorRangeEngine.swift # 色域選択・フローフィル
│   ├─ Layer.swift          # レイヤー / 合成エンジン
│   └─ TextRenderer.swift   # テキストのラスタライズ
├─ Model/                   # アプリ状態
│   ├─ ToolTypes.swift      # Tool / SelectionOperationMode 列挙型
│   ├─ AppModel.swift       # @Published 状態・キーボードハンドラ
│   ├─ AppModel+Operations.swift # 選択・変形・編集操作
│   └─ AppModel+File.swift  # ファイル保存・読込・エクスポート
├─ IO/ProjectIO.swift       # .pic 保存/読込・エクスポート
└─ Views/                   # SwiftUI ビュー一式
    ├─ ContentView.swift    # レイアウト・ツールパレット・ステータスバー
    ├─ CanvasView.swift     # キャンバス描画・ドラッグ操作・カーソル制御
    ├─ *OptionsView.swift   # ツールごとのオプションパネル
    ├─ LayerPalette.swift   # レイヤーパネル
    ├─ NavigatorPanel.swift # ナビゲーター
    ├─ LoupeWindow.swift    # ルーペ表示
    ├─ Helpers.swift        # NumberField・OptionSection・AnchorGrid
    └─ Dialogs.swift        # 各種ダイアログ
```

## 備考

- `.pic` は素の ZIP です。手動で解凍するとレイヤー PNG と manifest.json を取り出せます。
- 色域選択のアルゴリズム（連結成分ラベリング・Erosion・四隅サンプリング）は `ColorRangeEngine.swift` に実装されています。
