import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DQW ダメージ計算',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB5451B)),
        useMaterial3: true,
      ),
      home: const DamageCalcPage(),
    );
  }
}

// ──────────────────────────────────────────────
// 補正カテゴリ（①②③⑤⑥）の1入力エントリ
// ──────────────────────────────────────────────
class _BonusEntry {
  final TextEditingController controller;
  _BonusEntry() : controller = TextEditingController();

  void dispose() => controller.dispose();

  /// 現在の数値を返す（空・不正なら null）
  double? get value => double.tryParse(controller.text);
}

// ──────────────────────────────────────────────
// 1行分の全入力状態
// ──────────────────────────────────────────────
class _RowInput {
  final TextEditingController atkCtrl;   // 攻撃力
  final TextEditingController defCtrl;   // 守備力
  final TextEditingController skillCtrl; // スキル倍率(%)
  final TextEditingController weakCtrl;  // ④弱点(%)
  // 会心種別: 0=なし, 1=会心×1.60, 2=超会心×2.50
  int critType = 0;
  // バイキルト段階: 0=なし, 1=1段階(+20%), 2=2段階(+40%)
  int baikiltStage = 0;
  // プリセット選択インデックス（null=未選択/手動変更済み）
  int? presetIdx;
  // ①②③⑤⑥ の複数入力エントリ（index 0〜4 がそれぞれ対応）
  final List<List<_BonusEntry>> bonusGroups;

  _RowInput()
      : atkCtrl = TextEditingController(),
        defCtrl = TextEditingController(),
        skillCtrl = TextEditingController(),
        weakCtrl = TextEditingController(),
        bonusGroups = List.generate(3, (_) => [_BonusEntry()]);

  void dispose() {
    atkCtrl.dispose();
    defCtrl.dispose();
    skillCtrl.dispose();
    weakCtrl.dispose();
    for (final g in bonusGroups) {
      for (final e in g) { e.dispose(); }
    }
  }

  /// 全フィールドをクリア
  void clear(void Function(VoidCallback) setStateFn) {
    setStateFn(() {
      atkCtrl.clear();
      defCtrl.clear();
      skillCtrl.clear();
      weakCtrl.clear();
      critType = 0;
      baikiltStage = 0;
      presetIdx = null;
      for (int i = 0; i < bonusGroups.length; i++) {
        for (final e in bonusGroups[i]) { e.dispose(); }
        bonusGroups[i] = [_BonusEntry()];
      }
    });
  }

  /// src の内容をこの行にコピー
  void copyFrom(_RowInput src, void Function(VoidCallback) setStateFn) {
    setStateFn(() {
      atkCtrl.text   = src.atkCtrl.text;
      defCtrl.text   = src.defCtrl.text;
      skillCtrl.text = src.skillCtrl.text;
      weakCtrl.text  = src.weakCtrl.text;
      critType       = src.critType;
      baikiltStage   = src.baikiltStage;
      presetIdx      = src.presetIdx;
      for (int i = 0; i < bonusGroups.length; i++) {
        for (final e in bonusGroups[i]) { e.dispose(); }
        bonusGroups[i] = src.bonusGroups[i].map((e) {
          final ne = _BonusEntry();
          ne.controller.text = e.controller.text;
          return ne;
        }).toList();
      }
    });
  }
}

// ──────────────────────────────────────────────
// ダメージ計算ロジック
// ──────────────────────────────────────────────

/// 基礎ダメージ = floor(攻撃力/2) - floor(守備力/4)、最小1
int calcBase(int atk, int def) {
  final v = (atk ~/ 2) - (def ~/ 4);
  return v < 1 ? 1 : v;
}

/// 最終ダメージ
/// - skillPct: スキル倍率%（230入力 → ×2.30）
/// - bonusPcts: ①②③⑤⑥ 各カテゴリの合計ボーナス%（(100+合計)/100 を乗算）
/// - weakPct:  ④弱点%（150入力 → ×1.50、空欄=100）
int calcFinal(int base, double skillPct, List<double> bonusPcts, double weakPct) {
  double d = base.toDouble();
  d *= skillPct / 100.0;
  for (final b in bonusPcts) {
    d *= (100.0 + b) / 100.0;
  }
  d *= weakPct / 100.0;
  return d.floor();
}

/// 会心ダメージ = floor(最終 × 1.60)
int calcCrit(int finalDmg)  => (finalDmg * 1.60).floor();

/// 超会心ダメージ = floor(最終 × 2.50)
int calcSuper(int finalDmg) => (finalDmg * 2.50).floor();

// ──────────────────────────────────────────────
// メイン画面
// ──────────────────────────────────────────────
class DamageCalcPage extends StatefulWidget {
  const DamageCalcPage({super.key});
  @override
  State<DamageCalcPage> createState() => _DamageCalcState();
}

class _DamageCalcState extends State<DamageCalcPage> {
  // 3行分の入力状態
  final List<_RowInput> rows = List.generate(3, (_) => _RowInput());

  @override
  void dispose() {
    for (final r in rows) { r.dispose(); }
    super.dispose();
  }

  /// 全行クリア
  void clearAll() {
    for (final r in rows) { r.clear(setState); }
  }

  // 補正カテゴリのラベル（①②③ の順、④は別管理）
  static const List<String> _bonusLabels = [
    '① 斬撃&体技ダメージアップ',
    '② 属性ダメージアップ',
    '③ 系統特効',
  ];

  // 守備力プリセット定義（仮想敵/周回/ボス）
  static const _presets = [
    (label: '仮想敵', sub: '500',  def: 500),
    (label: '周回',   sub: '1200', def: 1200),
    (label: 'ボス',   sub: '1500', def: 1500),
  ];

  // ──────────── 計算結果取得 ────────────
  ({int base, int final_, int crit, int super_})? _calcRow(_RowInput row) {
    final atk      = int.tryParse(row.atkCtrl.text);
    final def      = int.tryParse(row.defCtrl.text);
    final skillPct = double.tryParse(row.skillCtrl.text);
    if (atk == null || def == null || skillPct == null) return null;
    if (atk <= 0 || skillPct <= 0) return null;

    // バイキルト倍率をこうげき力に乗算してから基礎ダメージを計算
    final baikiltMult = row.baikiltStage == 1 ? 1.20
                      : row.baikiltStage == 2 ? 1.40
                      : 1.00;
    final buffedAtk = (atk * baikiltMult).floor();
    final base = calcBase(buffedAtk, def < 0 ? 0 : def);

    final bonusPcts = List.generate(3, (i) => row.bonusGroups[i]
        .map((e) => e.value ?? 0.0)
        .fold(0.0, (a, b) => a + b));
    final weakPct = double.tryParse(row.weakCtrl.text) ?? 100.0;

    final finalDmg = calcFinal(base, skillPct, bonusPcts, weakPct);
    return (
      base:   base,
      final_: finalDmg,
      crit:   calcCrit(finalDmg),
      super_: calcSuper(finalDmg),
    );
  }

  // ──────────── 入力フィールド共通スタイル ────────────
  InputDecoration _dec(String hint, {String? suffix}) => InputDecoration(
        hintText: hint,
        suffixText: suffix,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      );

  Widget _intField(TextEditingController c, String hint, {String? suffix, VoidCallback? onChanged}) =>
      TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _dec(hint, suffix: suffix),
        onChanged: (_) {
          setState(() {});
          onChanged?.call();
        },
      );

  Widget _numField(TextEditingController c, String hint, {String? suffix}) =>
      TextField(
        controller: c,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
        ],
        decoration: _dec(hint, suffix: suffix),
        onChanged: (_) => setState(() {}),
      );

  // ──────────── 補正カテゴリUI（+追加/×削除） ────────────
  Widget _buildBonusGroup(int rowIdx, int gIdx) {
    final entries = rows[rowIdx].bonusGroups[gIdx];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _bonusLabels[gIdx],
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          ...List.generate(entries.length, (ei) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: entries[ei].controller,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                  ],
                  decoration: _dec('0', suffix: '%'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              // 2つ以上あるとき×ボタン表示
              if (entries.length > 1)
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    entries[ei].dispose();
                    entries.removeAt(ei);
                  }),
                ),
            ]),
          )),
          TextButton.icon(
            onPressed: () => setState(() => entries.add(_BonusEntry())),
            icon: const Icon(Icons.add, size: 13),
            label: const Text('追加', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 計算結果表示 ────────────
  Widget _buildResult(int rowIdx) {
    final row = rows[rowIdx];
    final res = _calcRow(row);

    if (res == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          '攻撃力・守備力・スキル倍率を入力',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      );
    }

    // 乱数幅（最小94%〜最大106%）
    final minDmg = (res.final_ * 0.94).floor();
    final maxDmg = (res.final_ * 1.06).floor();

    // 各結果行（選択中の会心種別をハイライト）
    Widget line(String label, int value, int critType) {
      final sel = row.critType == critType;
      return Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: sel
            ? BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                  fontSize: sel ? 13 : 12,
                  color: sel ? null : Colors.grey.shade600,
                )),
            Text(
              _fmt(value),
              style: TextStyle(
                fontSize: sel ? 20 : 13,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                color: sel
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('基礎ダメージ',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            Text(_fmt(res.base),
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 4),
        line('最終ダメージ',  res.final_, 0),
        // 乱数幅を最終ダメージ行の下に追記
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 2),
          child: Text(
            '最小 ${_fmt(minDmg)} 〜 最大 ${_fmt(maxDmg)}',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ),
        line('会心  ×1.60',  res.crit,   1),
        line('超会心 ×2.50', res.super_,  2),
      ],
    );
  }

  // カンマ区切り数値フォーマット
  String _fmt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    final offset = s.length % 3;
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (i - offset) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ──────────── コピーボタン ────────────
  Widget _buildCopyButtons(int rowIdx) {
    final btns = <Widget>[];
    if (rowIdx > 0) {
      btns.add(OutlinedButton.icon(
        onPressed: () => rows[rowIdx].copyFrom(rows[rowIdx - 1], setState),
        icon: const Icon(Icons.arrow_back, size: 13),
        label: Text('行$rowIdxからコピー',
            style: const TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ));
    }
    if (rowIdx < 2) {
      btns.add(OutlinedButton.icon(
        onPressed: () => rows[rowIdx + 1].copyFrom(rows[rowIdx], setState),
        icon: const Icon(Icons.arrow_forward, size: 13),
        label: Text('行${rowIdx + 2}へコピー',
            style: const TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ));
    }
    return Wrap(spacing: 4, runSpacing: 4, children: btns);
  }

  // ──────────── 1行カード ────────────
  Widget _buildRowCard(int rowIdx) {
    final row = rows[rowIdx];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ヘッダー行
            Row(children: [
              Text('行 ${rowIdx + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(child: _buildCopyButtons(rowIdx)),
            ]),

            // 計算結果（入力しながらリアルタイム確認できるよう上部に配置）
            _buildResult(rowIdx),
            const SizedBox(height: 10),

            // 攻撃力
            const Text('攻撃力', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            _intField(row.atkCtrl, '例: 1200'),
            const SizedBox(height: 8),

            // 守備力プリセット（守備力ラベルの上）
            Row(
              children: List.generate(_presets.length, (i) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_presets[i].label,
                          style: const TextStyle(fontSize: 11)),
                      Text(_presets[i].sub,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                  selected: row.presetIdx == i,
                  onSelected: (_) => setState(() {
                    row.defCtrl.text = _presets[i].def.toString();
                    row.weakCtrl.text = '100';
                    row.presetIdx = i;
                  }),
                  visualDensity: VisualDensity.compact,
                ),
              )),
            ),
            const SizedBox(height: 4),

            // 守備力（注記付き）
            const Text('守備力  ※実測推定値', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            // 手動変更時はプリセットハイライトを解除
            _intField(row.defCtrl, '例: 400',
                onChanged: () => row.presetIdx = null),
            const SizedBox(height: 8),

            // スキル倍率
            const Text('スキル倍率', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            _numField(row.skillCtrl, '例: 230', suffix: '%'),
            const SizedBox(height: 8),

            // バイキルト選択（スキル倍率の下）
            const Text('バイキルト', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('なし')),
                ButtonSegment(
                    value: 1,
                    label: Text('1段階\n+20%', textAlign: TextAlign.center)),
                ButtonSegment(
                    value: 2,
                    label: Text('2段階\n+40%', textAlign: TextAlign.center)),
              ],
              selected: {row.baikiltStage},
              onSelectionChanged: (v) =>
                  setState(() => row.baikiltStage = v.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(height: 8),

            // 会心種別
            const Text('会心種別', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('なし')),
                ButtonSegment(value: 1, label: Text('会心')),
                ButtonSegment(value: 2, label: Text('超会心')),
              ],
              selected: {row.critType},
              onSelectionChanged: (v) =>
                  setState(() => row.critType = v.first),
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact),
            ),
            const SizedBox(height: 12),

            // ①②③ 補正カテゴリ
            ...List.generate(3, (i) => _buildBonusGroup(rowIdx, i)),

            // ④ 弱点&耐性（単一フィールド）
            const Text('④ 弱点&耐性（敵側）',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            _numField(row.weakCtrl, '空欄=等倍(100)', suffix: '%'),
            const SizedBox(height: 2),
            const Text('弱点=150  /  等倍=100  /  耐性=50',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // ──────────── メインビルド ────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DQW ダメージ計算'),
        actions: [
          TextButton(onPressed: clearAll, child: const Text('全クリア')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final cards = List.generate(3, _buildRowCard);
            if (isWide) {
              // PC: 3列横並び
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: cards.asMap().entries.map((e) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left:  e.key == 0 ? 0 : 6,
                      right: e.key == 2 ? 0 : 6,
                    ),
                    child: e.value,
                  ),
                )).toList(),
              );
            }
            // スマホ: 縦1列
            return Column(
              children: cards
                  .map((c) =>
                      Padding(padding: const EdgeInsets.only(bottom: 12), child: c))
                  .toList(),
            );
          },
        ),
      ),
    );
  }
}
