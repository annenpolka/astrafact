# Runtime / state / provenance contract

## 正本

- 視覚編集の正本: 1モーション×1方向の .aseprite。
- 要求・時間・ゲームイベントの正本: asset.yaml と motion.yaml。
- 実際に検収する単位: 上記のハッシュ、書き出した全フレーム・時間・メタデータを束ねたcandidate manifest。
- .asepriteへ保存しただけで、生成PNGから身体・剣・髪のレイヤーが復元されるわけではない。
  元がフラットならフラットとして扱う。分離したレイヤーやmaskには別の来歴を付ける。
- v0.1では .aseprite を編集正本とし、Luaは履歴付きパッチにする。
  将来の「Luaそのものが正本の手続き生成」と同じファイルで双方向編集しない。

## 状態

spec_locked → candidate_created → mechanically_valid → visual_review
visual_review → evidence_needed / repair_planned / rejected / visual_pass
repair_planned → new_candidate → mechanically_valid → visual_review
visual_pass → exported → runtime_captured → runtime_review → released
どの段階でもbudget_exhausted / integrity_failure → checkpointed。

Astraが出すverdictは審査結果。releasedを直接書ける権限ではない。
コードが機械検査、SHA-256一致、実際のAstra利用レシート、runtime審査を合わせて承認する。
今回のキットはデータ契約と検査部品まで。上記状態機械の実行エンジンは未実装。


### 証拠待ちを行き止まりにしない

candidate審査で時間的な証拠が足りない場合は、合格前でもプレビュー専用の仮書き出しを許可する。
evidence_needed → preview_export → preview_capture → 新しいreview pack → visual_review。
これは配布・採用の許可ではない。ローカルプレビューで候補を評価し、最後は実ゲームで別途検収する。
画像の再生成と証拠の追加を混同しない。同一candidateでもpackが変わるので新しい審査へ紐づける。

## 承認の失効

次のいずれかが変われば、旧reviewをそのまま使わない:
- 画像、.aseprite、フレーム時間、イベント、pivot、パレット。
- asset/motion仕様、基準絵、必須審査項目、審査プロンプト。
- exporter、描画設定、runtime build、審査に使う画像自体。

保守的にpackを再生成・再審査するのがv0.1。
後に、変更していない判定だけを再利用する依存関係グラフを導入してよい。
履歴自体は消さず、新candidateを作り、前の承認済みcandidateへ戻せるようにする。

## Aseprite adapterの境界

このキットのフレーム番号は0始まり、時間はms。
Aseprite Luaの frameNumber は1始まり、Frame.duration は秒。
API境界だけで index + 1 と duration_ms / 1000 に変換する。

Aseprite Slice.pivot はslice.boundsの左上からのローカル座標。
canonical anchorから書くなら pivot_local = anchor_canvas - slice_bounds_origin。
Image:drawPixel はcel画像内座標。canvas座標からcel.positionを引く。
既存画像に直接drawPixelするだけではundo情報を作らないため、cloneと正しい更新手順を用いる。

これらは公式仕様:
- https://www.aseprite.org/api/frame
- https://www.aseprite.org/api/slice
- https://www.aseprite.org/api/image
- https://www.aseprite.org/docs/cli/

## 書き出し

v0.1は固定キャンバス、trimなし、回転packingなし、duplicate mergeなし。
フレーム削除・複製で無理に所定枚数を満たさない。

CLI例（実際のAsepriteで要スモークテスト）:

    aseprite --batch --list-tags --list-slices --list-layers \
      source/knight_001/attack_slash/E.aseprite \
      --format json-array --sheet-type rows --sheet-columns 4 \
      --data build/E.json --sheet build/E.png

空でない新しいbuildディレクトリへの上書きは原則禁止。親ディレクトリは実行前に作る。
.asepriteに保存された時間とmotion.yamlの不一致を検出し、暗黙の勝者を決めない。
asset仕様からフルキャンバスのanchor sliceを明示的に作り、存在と値を検証する。

## Runtime検証

専用プレビューだけで最終承認しない。実ゲームのimporter/renderer、背景、倍率で検証する。
clip frame index / monotonic timestamp / root position / event log / engine build ID を記録する。

in_placeの接地でも、身体の最下点や重心だけでは足を特定できない。
足アンカーと接地区間が別途承認されている場合だけ、それらを使う測定を行う。
重心・bbox・色数の急変は手掛かりであって自動的なNGではない。

## APIと実行権限

- 生成器adapterはsupported/unsupported/unknown、サイズ、フレーム数、方向、マスク・palette等の能力を返す。
- 要求に合わないモデルを使い、黙ってresize/padして帳尻を合わせない。
- secretsは環境変数/キーチェーン等から解決し、プロンプトや成果物へ保存しない。
- arbitrary Lua/shellを審査JSONから実行しない。許可済みexecutor＋検証済みパラメータへ限定する。
- 外部ツールは作業コピーで実行し、元の採用候補を直接変更しない。
- providerのマスク保持は信用せず、許可領域だけ元画像へ合成し、その後で再審査する。
- submit後timeoutはjob状態を照合するまで再送しない。idempotency非対応ならpaid POSTを盲目的にretryしない。

## Astra監査レシート（ホストが記録。モデルには自己申告させない）

    run_id
    actual_model_id / selected_harness_mode
    reviewer_prompt_sha256
    review_pack_sha256
    sent_image_id_and_sha256[]
    observed_playback_mode
    provider_request_or_session_id
    started_at / finished_at
    usage_if_reported
    billed_cost_if_reported

Proという表示名、APIのモデル名、ハーネスの選択肢を同一視しない。
今回のキットに実際のAstra接続コードはない。まず既存の利用環境でpackを添付し、JSON出力を検査する。
usage/costが取得できなければnull。推定と実測を別フィールドにし、架空の値で埋めない。

## 費用停止条件

上限はホストが管理し、モデルに変更させない。
上限に達したらcheckpoint。画質の合格基準は変えない。
採用1クリップ当たりの費用 = 生成 + 全候補の審査 + 修正 + 再審査 + runtime確認。
候補設計・基準絵の共通費は別計上する。
具体的な上限額は実測後に設定する。金額未設定のまま有料自動呼出しを開始しない。
