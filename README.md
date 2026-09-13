# Astrafact — Contract Kit v0.1

Astraを全ての視覚的な品質判断の中核に置き、判断の周囲をコードで規格化するための設計・検査キット。
生成器のAPI、Astraへの接続、Aseprite、実ゲームrendererはまだ接続していない。

## 何があるか

| ファイル | 役割 |
|---|---|
| `SPEC.md` | 仕様・プロンプト・具体例をまとめた設計書 |
| `schemas/asset.schema.json` | アセットの座標・色・個体・runtime要求 |
| `schemas/motion.schema.json` | フレーム時間・イベント・動作要求 |
| `schemas/review-pack.schema.json` | 審査画像・比較板セル・ハッシュの対応 |
| `schemas/review.schema.json` | Astraの観察・判定・修正候補 |
| `schemas/repair-plan.schema.json` | 実行器へ渡す修正範囲と保存条件 |
| `examples/` | 架空の1キャラ・東向き・4フレーム攻撃のデータ例 |
| `prompts/` | 審査・審査依頼・修正計画のプロンプト |
| `policies/routing.yaml` | 修正ルーティング・予算停止・リリース条件の設計 |
| `docs/review-board.md` | 比較板の寸法・座標・時間・入力仕様 |
| `docs/runtime-and-state.md` | 正本・失効・Aseprite境界・runtime・実行権限 |
| `tools/contracts.py` | JSON Schema・ファイル間制約・座標変換・参照ハッシュ検査 |
| `tools/pixel_guard.py` | 修正マスク外への変更検出 |
| `tests/` | 純粋な契約・ピクセル比較ロジックの単体テスト |

## 最初に固定する判断

1. 全視覚ゲートをAstraが担当する。待機・ポーリング・ファイル操作は通常コードが担当する。
2. 総合点は使わず、必須条件ごとのpass/fail/not_observableを扱う。
3. 画像が良いことと実行結果が良いことを別々に検収する。
4. SHA-256に紐づけた審査結果だけを使う。画像変更後に古い合格を流用しない。
5. regionは観察位置の提案。確定マスク、予算、実行器の権限はホスト側で管理する。

## 動作確認

Python 3.11以降を想定。requirementsはこの環境でテストしたバージョンで、最新版であるという意味ではない。

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
python tools/validate.py --dir examples
python -m unittest discover -s tests -v
```

最初のコマンドは**スキーマとファイル間の整合性**を検査する。
画像や実ゲームの品質を検査するものではない。

実ファイルが揃ったプロジェクトでのみ:

```sh
python tools/validate.py --root /path/to/project --dir asset-contracts --verify-artifacts
```

`--dir`の中に `asset.yaml`, `motion.yaml`, `review-pack.json`, `review.json` を置く。
`repair-plan.json`は存在する場合のみ検査する。
参照パスはすべて`--root`からの相対パス。外部URLの自動取得はしない。
`examples`に対して`--verify-artifacts`を実行すると、**意図通り失敗する**。
架空のmanifestと、実在しない画像・マスクを本番証拠として通さないため。

## スコープと未実装

実装済み: JSON/YAML読み込み、重複キー検出、5種のスキーマ、主要なファイル間制約、
全フレームの証拠掲載確認、座標変換、ローカル参照のハッシュ確認、バイナリマスク外変更検出。

未実装/未検証:
- 生成器adapterと課金ジョブの実行・復旧。
- Aseprite Luaの実行と実際の`.aseprite`編集・export。
- 比較板を実画像から描画するツール。
- Astra呼び出し、実際のモデル・利用モードの固定、利用量の取得。
- パレット/alpha/イベント等の実アセット全検査、実ゲームcapture。
- 状態機械、予算台帳、実行許可、最終release処理。
- Astraの実際の審査精度・見落とし率・費用・遅延の評価。

サンプルのreviewは架空で、Astraが素材を審査した記録ではない。
ハッシュ例のうち実画像に相当する値もダミー。契約検査に合格しても実行許可は生じない。
Aseprite本体・フォント・第三者のアート素材・APIキーは含めていない。

## 事実として参照した公式仕様

以下は外部ツールの仕様。その他の規格値や手順はこのキットの設計提案。

- JSON Schema Draft 2020-12: https://json-schema.org/draft/2020-12
- Aseprite CLI、sheet/data、タグとsliceのexport: https://www.aseprite.org/docs/cli/
- Aseprite Luaの1始まりフレーム番号・秒単位duration: https://www.aseprite.org/api/frame
- Slice pivotのローカル座標: https://www.aseprite.org/api/slice
- Image座標とdrawPixelのundoに関する注意: https://www.aseprite.org/api/image
- OpenAIの画像入力形式・リサイズ・画像認識の制約: https://developers.openai.com/api/docs/guides/images-vision

画像APIの対応形式に非アニメーションGIFが記載されていることと、
別のハーネスで動画を再生して観察できるかは別問題。
このキットは動画対応や1px位置特定の精度をモデル名だけで仮定しない。

## 次の実証単位

手元で権利を持つ基準絵を1枚用意し、1方向・4フレームのクリップを取り込む。
全フレームを比較板化し、Astraに実際に見せ、1箇所を直して全体を再審査する。
これを実rendererへ通すまでを最初の縦切りとする。
8方向・大量生成は、その往復で不明点と費用を測ってから拡張する。
