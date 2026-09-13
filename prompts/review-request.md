# ホストが埋める依頼テンプレート

次の review pack の {{stage}} 審査を行う。

pack_id: {{pack_id}}
pack_sha256: {{pack_sha256}}
candidate_id: {{candidate_id}}

## Asset specification
{{asset_yaml}}

## Motion specification
{{motion_yaml}}

## Review pack
{{review_pack_json}}

## 機械検査
{{machine_report_json}}

## 実際に添付した画像
{{image_id_to_attachment_table}}

## 実際に観測できる再生証拠
{{playback_evidence_and_limitations}}

## 出力スキーマ
{{review_schema_json}}

prompts/reviewer.md に従い、JSONだけを返す。

---
注意: {{...}} はこのキット独自のテンプレート表記。モデルAPIの構文ではない。
パス文字列を埋めるだけで画像が送信されるわけではない。
ホストは画像バイト列を実際の利用環境に添付し、対応表を必ず添える。
