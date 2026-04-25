# dqw_damage_calc 修正指示書
## Claude Codeへの依頼内容

---

## 背景・前提

- **既存の `lib/main.dart` を修正する**（新規作成ではない）
- テーマカラー（`0xFFB5451B`）・Material3・カード構成・3行比較レイアウト・コピー機能はそのまま維持
- スマホ優先レスポンシブUI（PC横並び・スマホ縦も維持）

---

## 修正・追加する点（5箇所）

### 修正1：会心・超会心の倍率を正しい値に修正

既存の倍率が誤っているので修正する。

```dart
// 変更前
int calcCrit(int finalDmg)  => (finalDmg * 1.25).floor();
int calcSuper(int finalDmg) => (finalDmg * 1.50).floor();

// 変更後
int calcCrit(int finalDmg)  => (finalDmg * 1.60).floor();
int calcSuper(int finalDmg) => (finalDmg * 2.50).floor();
```

表示ラベルも合わせて変更：
- `'会心  ×1.25'`  → `'会心  ×1.60'`
- `'超会心 ×1.50'` → `'超会心 ×2.50'`

---

### 修正2：最終ダメージに乱数幅（最小/最大）を追記表示

`_buildResult` の結果表示部分で、最終ダメージ行の下に乱数幅を小さく追記する。

```
最終ダメージ    1,312
最小 1,233 〜 最大 1,390    ← 追加（fontSize:10, color:grey）
```

計算式：
```dart
final minDmg = (finalDmg * 0.94).floor();
final maxDmg = (finalDmg * 1.06).floor();
```

---

### 修正3：バイキルト選択を追加

`_RowInput` に `int baikiltStage = 0`（0=なし/1=1段階/2=2段階）を追加。

各行カードの「スキル倍率」フィールドの**下**に `SegmentedButton` を追加：

```dart
SegmentedButton<int>(
  segments: const [
    ButtonSegment(value: 0, label: Text('なし')),
    ButtonSegment(value: 1, label: Text('1段階\n+20%', textAlign: TextAlign.center)),
    ButtonSegment(value: 2, label: Text('2段階\n+40%', textAlign: TextAlign.center)),
  ],
  selected: {row.baikiltStage},
  onSelectionChanged: (v) => setState(() => row.baikiltStage = v.first),
  style: const ButtonStyle(visualDensity: VisualDensity.compact),
),
```

**計算ロジックへの反映（重要）**：
バイキルトはこうげき力への乗算。スキルダメージへの乗算ではない。

```dart
// _calcRow 内で atk を取得した直後に適用
final baikiltMult = row.baikiltStage == 1 ? 1.20
                  : row.baikiltStage == 2 ? 1.40
                  : 1.00;
final buffedAtk = (atk * baikiltMult).floor();
final base = calcBase(buffedAtk, def < 0 ? 0 : def);
// 以降の計算は buffedAtk ではなく base を使う（既存と同じ）
```

`_RowInput.clear()` と `_RowInput.copyFrom()` にも `baikiltStage` の初期化・コピーを忘れずに追加。

---

### 修正4：プリセットボタンを追加

`_RowInput` に `int? presetIdx`（null=未選択/0=仮想敵/1=周回想定/2=ボス想定）を追加。

各行カードの守備力ラベルの**上**に3ボタンを横並びで配置：

```dart
// プリセット定義（_DamageCalcState のクラス定数として追加）
static const _presets = [
  (label: '仮想敵',   def: 500),
  (label: '周回想定', def: 1200),
  (label: 'ボス想定', def: 1500),
];
```

表示：

```dart
Row(
  children: List.generate(_presets.length, (i) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: ChoiceChip(
      label: Text(_presets[i].label, style: const TextStyle(fontSize: 11)),
      selected: row.presetIdx == i,
      onSelected: (_) => setState(() {
        row.defCtrl.text = _presets[i].def.toString();
        row.weakCtrl.text = '100';
        row.presetIdx = i;
      }),
      visualDensity: VisualDensity.compact,
    ),
  )),
)
```

守備力フィールドの `onChanged` で `row.presetIdx = null` にセット（手動変更でハイライト解除）。

---

### 修正5：守備力ラベルに注記追加

```dart
// 変更前
const Text('守備力', style: TextStyle(fontSize: 12)),

// 変更後
const Text('守備力  ※実測推定値', style: TextStyle(fontSize: 12)),
```

---

## 変更しないもの

以下はそのまま維持する：

- テーマカラー・AppBarスタイル
- 3行比較レイアウト（PC横並び・スマホ縦）
- ①②③⑤⑥補正カテゴリの複数入力UI（追加/削除ボタン）
- ④弱点&耐性の自由入力フィールド
- 行間コピーボタン（前行からコピー・次行へコピー）
- 全クリアボタン
- カンマ区切りフォーマット（`_fmt`）
- 基礎ダメージ表示
- 会心種別のハイライト表示ロジック

---

## 作業完了の確認項目

- [ ] `flutter analyze` でエラーなし
- [ ] 会心倍率が ×1.60、超会心が ×2.50 になっている
- [ ] バイキルト1段階でこうげき力が1.2倍されてから基礎ダメージが計算される
- [ ] プリセットボタンで守備力がセットされる
- [ ] 手動で守備力を変更するとプリセットのハイライトが消える
- [ ] 乱数の最小/最大が最終ダメージ行の下に表示される
- [ ] `_RowInput.clear()` と `copyFrom()` でバイキルト・プリセットもリセット/コピーされる

---

## 計算式の参考（DQW検証済み）

```
基礎ダメージ = floor(こうげき力×バイキルト倍率 / 2) − floor(守備力 / 4)
※基礎ダメージ < 1 の場合は 1

最終ダメージ =
  基礎ダメージ
  × (スキル倍率 / 100)
  × ((100 + 斬撃体技UP) / 100)
  × ((100 + 属性ダメージUP) / 100)
  × ((100 + 系統特攻) / 100)
  × (弱点耐性 / 100)

乱数：最小 = floor(最終 × 0.94)、最大 = floor(最終 × 1.06)
会心：floor(最終 × 1.60)
超会心：floor(最終 × 2.50)
```
