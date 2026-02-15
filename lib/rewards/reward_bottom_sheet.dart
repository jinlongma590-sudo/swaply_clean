// lib/rewards/reward_bottom_sheet.dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:swaply/services/reward_after_publish.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_fortune_wheel/flutter_fortune_wheel.dart';
import 'package:rxdart/rxdart.dart';

// ✅ 用你项目现有的安全导航 & 奖励中心页
import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/pages/reward_center_page.dart';
import 'package:swaply/pages/reward_rules_page.dart';
import 'package:swaply/core/qa_keys.dart'; // QaKeys

class RewardBottomSheet extends StatefulWidget {
  const RewardBottomSheet({
    super.key,
    required this.data,
    this.campaignCode = 'launch_v1',
    this.listingId,
  });

  final Map<String, dynamic> data;
  final String campaignCode;
  final String? listingId;

  @override
  State<RewardBottomSheet> createState() => _RewardBottomSheetState();
}

class _RewardBottomSheetState extends State<RewardBottomSheet>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _data;

  bool _spinning = false;
  Map<String, dynamic>? _spinResp;

  // ✅ FortuneWheel stream
  final StreamController<int> _selected = BehaviorSubject<int>();

  late final AnimationController _ctl;
  late final Animation<double> _anim;

  double _turnsTarget = 0;
  double _turnsFrom = 0;
  double _turnsNow = 0;

  // ✅ 方案A：后端直接发 reward 但 spins==0 时，补一段"开盒动画"
  bool _autoRevealArmed = false;
  bool _autoRevealing = false;

  // ✅ 转盘配色
  static const Color kPrimaryGreen = Color(0xFF4CAF50);
  static const Color kDarkGreen = Color(0xFF2E7D32);
  static const Color kAccentGreen = Color(0xFF66BB6A);

  static const List<List<Color>> kSliceGradients = [
    [Color(0xFF4CAF50), Color(0xFF66BB6A)],
    [Color(0xFF2196F3), Color(0xFF42A5F5)],
    [Color(0xFF43A047), Color(0xFF66BB6A)],
    [Color(0xFFFF6F00), Color(0xFFFF8F00)],
    [Color(0xFF616161), Color(0xFF9E9E9E)],
    [Color(0xFFD81B60), Color(0xFFEC407A)],
  ];

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.data);

    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _anim = CurvedAnimation(parent: _ctl, curve: Curves.easeOutCubic);

    _ctl.addListener(() {
      final t = _anim.value;
      _turnsNow = _lerp(_turnsFrom, _turnsTarget, t);
      if (mounted) setState(() {});
    });

    _ctl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _turnsFrom = _turnsTarget;
      }
    });

    _autoRevealArmed = _shouldAutoReveal();
    if (_autoRevealArmed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoRevealIfNeeded();
      });
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _selected.close();
    super.dispose();
  }

  // -------------------- Helpers --------------------

  bool get ok => _data['ok'] == true;

  int _toInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

  bool _toBool(dynamic v) {
    if (v is bool) return v;
    final s = (v ?? '').toString().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  int get qualifiedCount => _toInt(_data['qualified_count']);
  int get points => _toInt(_data['airtime_points']);
  int get spins => _toInt(_data['spins']);

  String get milestoneProgress {
    final v = (_data['milestone_progress_text'] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
    return (_data['milestone_progress'] ?? '').toString();
  }

  List<int> get milestoneSteps {
    final raw = _data['milestone_steps'];
    if (raw is List) {
      final out = <int>[];
      for (final e in raw) {
        final n = _toInt(e);
        if (n > 0) out.add(n);
      }
      out.sort();
      return out;
    }
    return const [1, 5, 10, 20, 30];
  }

  bool get spinGrantedNow => _toBool(_data['spin_granted_now']);
  int get spinsAddedNow => _toInt(_data['spins_added_now']);
  int get spinGrantTriggerN => _toInt(_data['spin_grant_trigger_n']);

  Map<String, dynamic>? get reward => _data['reward'] is Map
      ? Map<String, dynamic>.from(_data['reward'] as Map)
      : null;

  List<Map<String, dynamic>> get pool {
    final raw = _data['pool'];
    if (raw is List) {
      return raw
          .map((e) {
        if (e is Map) return Map<String, dynamic>.from(e);
        return <String, dynamic>{};
      })
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [];
  }

  bool get loopEnabled => _toBool(_data['spin_loop_enabled']);
  int get loopNextAt => _toInt(_data['spin_loop_next_at']);
  int get loopRemaining => _toInt(_data['spin_loop_remaining']);
  int get loopInterval => _toInt(_data['spin_loop_interval']);
  int get loopStartAt => _toInt(_data['spin_loop_start_at']);

  bool get hasLoopInfo =>
      loopEnabled &&
          loopNextAt > 0 &&
          loopRemaining > 0 &&
          loopInterval > 0 &&
          loopStartAt > 0;

  String get loopHintText {
    final backendText = (_data['spin_loop_progress_text'] ?? '').toString().trim();
    if (backendText.isNotEmpty) return backendText;

    if (!hasLoopInfo) return '';
    return 'Next loop spin in $loopRemaining listings (at #$loopNextAt)';
  }

  bool get canSpin =>
      ok && spins > 0 && !_spinning && (widget.listingId?.isNotEmpty ?? false);

  String _formatScope(String scope) {
    const names = {'category': 'Category', 'search': 'Search', 'trending': 'Trending'};
    return names[scope.toLowerCase()] ?? scope;
  }



  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  // -------------------- ✅ 长标题缩写/两行化 --------------------

  _WheelItem _compactWheelText(String rawTitle) {
    var t = rawTitle.trim();
    if (t.isEmpty) return _WheelItem(mainText: 'REWARD', subText: '');

    final lower = t.toLowerCase();

    // 1) "Airtime Points + 10" => main: 10 / sub: AIRTIME
    if (t.contains('+')) {
      final parts = t.split('+');
      if (parts.length == 2) {
        final left = parts[0].trim().toUpperCase();
        final right = parts[1].trim();

        String left2 = left;
        if (left2.contains('AIRTIME')) left2 = 'AIRTIME';
        if (left2.contains('POINT')) left2 = 'POINTS';
        if (left2.contains('CREDIT')) left2 = 'CREDITS';

        return _WheelItem(mainText: right, subText: left2);
      }
    }

    // 2) boost/pin/featured
    if (lower.contains('boost') || lower.contains('pin') || lower.contains('featured')) {
      if (lower.contains('category')) return _WheelItem(mainText: 'CAT', subText: 'BOOST');
      if (lower.contains('search')) return _WheelItem(mainText: 'SEARCH', subText: 'BOOST');
      if (lower.contains('trend')) return _WheelItem(mainText: 'TREND', subText: 'BOOST');

      final first = t.split(RegExp(r'\s+')).first.toUpperCase();
      final main = first.length > 8 ? first.substring(0, 8) : first;
      return _WheelItem(mainText: main, subText: 'BOOST');
    }

    // 3) 空奖/再来一次（理论上不应出现，保留兼容性）
    if (lower.contains('none') ||
        lower.contains('try') ||
        lower.contains('again') ||
        lower.contains('no reward') ||
        lower.contains('better luck')) {
      return _WheelItem(mainText: '100 PTS', subText: 'AIR'); // 改为100 PTS大奖显示
    }

    // 4) $1 Airtime大奖特殊处理
    if (lower.contains('\$1') || t.contains('\$1') || lower.contains('100 pts') || lower.contains('100 points')) {
      return _WheelItem(mainText: '100 PTS', subText: 'AIR');
    }
    
    // 5) Airtime points with numbers: "5 Airtime Points" -> "5 PTS"
    final pointsMatch = RegExp(r'^(\d+)\s+(?:airtime\s+)?points?', caseSensitive: false).firstMatch(lower);
    if (pointsMatch != null) {
      final number = pointsMatch.group(1) ?? '';
      if (number.isNotEmpty) return _WheelItem(mainText: '$number PTS', subText: 'POINTS');
    }
    
    // 6) Airtime/Points/Credits (generic fallback)
    if (lower.contains('airtime')) return _WheelItem(mainText: 'AIRTIME', subText: 'POINTS');
    if (lower.contains('points')) return _WheelItem(mainText: 'POINTS', subText: '');
    if (lower.contains('credit')) return _WheelItem(mainText: 'CREDIT', subText: '');

    // 7) 3-day / 5 day
    final dayMatch = RegExp(r'(\d+)\s*-\s*day|\b(\d+)\s*day\b', caseSensitive: false)
        .firstMatch(t);
    if (dayMatch != null) {
      final n = dayMatch.group(1) ?? dayMatch.group(2) ?? '';
      if (n.isNotEmpty) return _WheelItem(mainText: '$n-DAY', subText: 'BOOST');
    }

    // 8) 默认：主词<=8，其余<=10
    final words = t.split(RegExp(r'\s+')).where((e) => e.trim().isNotEmpty).toList();
    if (words.length == 1) {
      final w = words.first.toUpperCase();
      return _WheelItem(mainText: w.length > 8 ? w.substring(0, 8) : w, subText: '');
    }

    final main = words.first.toUpperCase();
    final rest = words.skip(1).join(' ').toUpperCase();
    return _WheelItem(
      mainText: main.length > 8 ? main.substring(0, 8) : main,
      subText: rest.length > 10 ? rest.substring(0, 10) : rest,
    );
  }

  // -------------------- 打开奖励中心 --------------------

  void _openRewardCenter() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SafeNavigator.push(
        MaterialPageRoute(builder: (_) => const RewardCenterPage()),
      );
    });
  }

  void _openRewardRules() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SafeNavigator.push(
        MaterialPageRoute(
          builder: (_) => RewardRulesPage(
            pool: pool,
          ),
        ),
      );
    });
  }

  Widget _goRewardsButton({String label = 'Go to Reward Center'}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _openRewardCenter,
        icon: const Icon(Icons.emoji_events_rounded, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _rulesIconButton() {
    return IconButton(
      key: const Key(QaKeys.rewardRulesBtn),
      tooltip: 'Rules & Odds',
      onPressed: _openRewardRules,
      icon: const Icon(Icons.info_outline),
    );
  }

  // -------------------- Scheme A: Auto reveal --------------------

  bool _shouldAutoReveal() {
    if (!ok) return false;
    if (_spinResp != null) return false;
    if (spins > 0) return false;
    final r = reward;
    if (r == null) return false;
    return true;
  }

  Future<void> _autoRevealIfNeeded() async {
    if (!mounted) return;
    if (!_autoRevealArmed) return;
    if (_autoRevealing) return;
    if (!_shouldAutoReveal()) return;

    setState(() {
      _autoRevealing = true;
      _spinning = true;
    });

    final items = _getWheelItems();
    final targetIndex = Random().nextInt(items.length);
    _selected.add(targetIndex);

    await Future.delayed(const Duration(milliseconds: 4500));
    if (!mounted) return;

    final r = reward ?? <String, dynamic>{};
    final resp = <String, dynamic>{
      'ok': true,
      'spins_left': 0,
      'reward': r,
      'airtime_points': points,
      'qualified_count': qualifiedCount,
      'spin_loop_enabled': _data['spin_loop_enabled'],
      'spin_loop_next_at': _data['spin_loop_next_at'],
      'spin_loop_remaining': _data['spin_loop_remaining'],
      'spin_loop_interval': _data['spin_loop_interval'],
      'spin_loop_start_at': _data['spin_loop_start_at'],
      'spin_loop_progress_text': _data['spin_loop_progress_text'],
      'milestone_progress_text': _data['milestone_progress_text'],
      'milestone_steps': _data['milestone_steps'],
      'spin_granted_now': _data['spin_granted_now'],
      'spins_added_now': _data['spins_added_now'],
      'spin_grant_trigger_n': _data['spin_grant_trigger_n'],
    };

    setState(() {
      _spinResp = resp;
      _spinning = false;
      _autoRevealing = false;
      _autoRevealArmed = false;
    });
  }

  // -------------------- Actions --------------------

  Future<void> _spin() async {
    if (!ok) return;
    if (spins <= 0) return;
    if (_spinning) return;

    if (widget.listingId == null || widget.listingId!.isEmpty) {
      setState(() {
        _spinResp = {
          'ok': false,
          'reason': 'listing_id_missing',
          'error': 'listingId is required to spin.',
        };
      });
      return;
    }

    setState(() {
      _spinning = true;
      _spinResp = null;
    });

    final items = _getWheelItems();
    final targetIndex = Random().nextInt(items.length);
    _selected.add(targetIndex);

    try {
      final resp = await RewardAfterPublish.I.spin(
        requestId: const Uuid().v4(),
        campaignCode: widget.campaignCode,
        listingId: widget.listingId,
      );

      await Future.delayed(const Duration(milliseconds: 4500));
      if (!mounted) return;

      final map = _asMap(resp);

      if (map['ok'] == true) {
        if (map.containsKey('spins_left')) _data['spins'] = _toInt(map['spins_left']);
        if (map.containsKey('reward')) _data['reward'] = map['reward'];
        if (map.containsKey('airtime_points')) _data['airtime_points'] = _toInt(map['airtime_points']);
        if (map.containsKey('qualified_count')) _data['qualified_count'] = _toInt(map['qualified_count']);

        const loopKeys = [
          'spin_loop_enabled',
          'spin_loop_next_at',
          'spin_loop_remaining',
          'spin_loop_interval',
          'spin_loop_start_at',
          'spin_loop_progress_text',
        ];
        for (final k in loopKeys) {
          if (map.containsKey(k)) _data[k] = map[k];
        }

        const milestoneKeys = [
          'milestone_progress_text',
          'milestone_steps',
          'spin_granted_now',
          'spins_added_now',
          'spin_grant_trigger_n',
        ];
        for (final k in milestoneKeys) {
          if (map.containsKey(k)) _data[k] = map[k];
        }
      }

      setState(() {
        _spinResp = map.isEmpty
            ? {
          'ok': false,
          'reason': 'unexpected_response',
          'error': 'spin() returned non-map response: ${resp.runtimeType}',
        }
            : map;
        _spinning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _spinning = false;
        _spinResp = {
          'ok': false,
          'reason': 'exception',
          'error': e.toString(),
        };
      });
    }
  }

  // -------------------- Wheel Items --------------------

  List<_WheelItem> _getWheelItems() {
    if (pool.isEmpty) {
      return [
        _WheelItem(mainText: '5', subText: 'POINTS'),
        _WheelItem(mainText: 'CAT', subText: 'BOOST'),
        _WheelItem(mainText: '10', subText: 'POINTS'),
        _WheelItem(mainText: 'SEARCH', subText: 'BOOST'),
        _WheelItem(mainText: '\$1', subText: 'AIR'),
        _WheelItem(mainText: 'TREND', subText: 'BOOST'),
      ];
    }

    return pool.take(8).map((item) {
      final title = (item['title'] ?? 'Reward').toString();
      return _compactWheelText(title);
    }).toList();
  }

  // -------------------- UI Shell --------------------

  /// ✅ 修复 ExpansionTile 展开后 Column 溢出：让底部内容可滚动
  Widget _wrap(Widget child) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _handle() {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _iconBubble(IconData icon, Color color) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 36, color: color),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.blue.withOpacity(0.18)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _infoBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.flag, color: Colors.blue[700], size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: Colors.blue[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loopBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Icon(Icons.casino, color: Colors.green[700], size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.green[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _milestoneStrip() {
    final steps = milestoneSteps;
    if (steps.isEmpty) return const SizedBox.shrink();

    final c = qualifiedCount;

    Color chipColor(bool done) => done ? Colors.green : Colors.grey;
    Color bgColor(bool done) =>
        done ? Colors.green.withOpacity(0.10) : Colors.grey.withOpacity(0.10);
    Color borderColor(bool done) =>
        done ? Colors.green.withOpacity(0.25) : Colors.grey.withOpacity(0.25);

    Widget chip(int n) {
      final done = c >= n;
      final justGranted = spinGrantedNow && spinGrantTriggerN == n && spinsAddedNow > 0;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor(done),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor(done)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 14,
              color: chipColor(done),
            ),
            const SizedBox(width: 6),
            Text(
              '#$n',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: done ? Colors.green[700] : Colors.grey[700],
              ),
            ),
            if (justGranted) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.orange.withOpacity(0.28)),
                ),
                child: Text(
                  '+$spinsAddedNow',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.orange[800],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Milestone spins',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: steps.map(chip).toList(),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 22, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  // -------------------- FortuneWheel --------------------

  Widget _fortuneWheel() {
    final items = _getWheelItems();

    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: kPrimaryGreen.withOpacity(0.2),
                width: 4,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.all(8),
            child: FortuneWheel(
              selected: _selected.stream,
              animateFirst: false,
              physics: CircularPanPhysics(
                duration: const Duration(milliseconds: 4500),
                curve: Curves.decelerate,
              ),
              indicators: <FortuneIndicator>[
                FortuneIndicator(
                  alignment: Alignment.topCenter,
                  child: Transform.translate(
                    offset: const Offset(0, -10),
                    child: TriangleIndicator(
                      color: kPrimaryGreen,
                      width: 28,
                      height: 32,
                    ),
                  ),
                ),
              ],
              items: List.generate(items.length, (index) {
                final item = items[index];
                final gradient = kSliceGradients[index % kSliceGradients.length];

                return FortuneItem(
                  child: Container(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.mainText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.0,
                              height: 1.0,
                              shadows: [
                                Shadow(
                                  color: Colors.black26,
                                  blurRadius: 3,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                          ),
                          if (item.subText.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              item.subText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.w800,
                                color: Colors.white.withOpacity(0.95),
                                letterSpacing: 0.0,
                                height: 1.0,
                                shadows: const [
                                  Shadow(color: Colors.black12, blurRadius: 2),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  style: FortuneItemStyle(
                    color: gradient[0],
                    borderColor: Colors.white,
                    borderWidth: 3,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }



  // -------------------- Build --------------------

  @override
  Widget build(BuildContext context) {
    if (!ok) return _buildError(context);
    if (_autoRevealing) return _buildAutoRevealMode(context);
    if (_spinResp != null) return _buildSpinResult(context, _spinResp!);
    if (spins > 0) return _buildSpinMode(context);
    if (reward != null) return _buildRewardMode(context, reward!);
    return _buildProgressMode(context);
  }

  // -------------------- Modes --------------------

  Widget _buildError(BuildContext context) {
    final subtitle = _data['error']?.toString() ?? _data['reason']?.toString() ?? 'Unknown error';

    return _wrap(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(),
          _iconBubble(Icons.error_outline, Colors.red),
          const SizedBox(height: 12),
          const Text('Reward Failed', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          const SizedBox(height: 16),
          _goRewardsButton(),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Close', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoRevealMode(BuildContext context) {
    return _wrap(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(),
          Row(
            children: [
              const Expanded(
                child: Text('🎰 Reward Center', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              _rulesIconButton(),
              _pill('Revealing...'),
            ],
          ),
          const SizedBox(height: 10),
          _fortuneWheel(),
          const SizedBox(height: 8),
          Text('Qualified: $qualifiedCount • Points: $points', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 12),
          _milestoneStrip(),
          if (milestoneProgress.isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoBox(milestoneProgress),
          ],
          if (loopHintText.isNotEmpty) ...[
            const SizedBox(height: 10),
            _loopBox(loopHintText),
          ],
          const SizedBox(height: 12),

        ],
      ),
    );
  }

  Widget _buildSpinMode(BuildContext context) {
    final listingOk = widget.listingId != null && widget.listingId!.isNotEmpty;

    return _wrap(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(),
          Row(
            children: [
              const Expanded(
                child: Text('🎰 Reward Center', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              _rulesIconButton(),
              _pill('Spins: $spins'),
            ],
          ),
          const SizedBox(height: 10),
          _fortuneWheel(),
          const SizedBox(height: 8),
          Text('Qualified: $qualifiedCount • Points: $points', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 12),
          _milestoneStrip(),
          if (milestoneProgress.isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoBox(milestoneProgress),
          ],
          if (loopHintText.isNotEmpty) ...[
            const SizedBox(height: 10),
            _loopBox(loopHintText),
          ],
          const SizedBox(height: 12),

          const SizedBox(height: 14),
          if (!listingOk) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Spin requires listingId. Please reopen from the publish flow.',
                      style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canSpin ? _spin : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _spinning
                  ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Text('SPIN NOW', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
          _goRewardsButton(),
        ],
      ),
    );
  }

  Widget _buildSpinResult(BuildContext context, Map<String, dynamic> resp) {
    if (resp['ok'] != true) {
      final reason = resp['reason']?.toString() ?? resp['error']?.toString() ?? 'Spin failed';

      return _wrap(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handle(),
            _iconBubble(Icons.warning_amber_rounded, Colors.orange),
            const SizedBox(height: 12),
            const Text('Spin Failed', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(reason, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            const SizedBox(height: 16),
            _goRewardsButton(),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => setState(() => _spinResp = null),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Back', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
    }

    final spinsLeft = _toInt(resp['spins_left']);
    final r = resp['reward'] is Map
        ? Map<String, dynamic>.from(resp['reward'] as Map)
        : <String, dynamic>{};

    final typeRaw = (r['result_type'] ?? '').toString();
    final type = typeRaw == 'featured' ? 'boost_coupon' : typeRaw;

    String title;
    String subtitle;
    IconData icon;
    Color iconColor;

    if (type == 'boost_coupon') {
      final scope = (r['pin_scope'] ?? 'category').toString();
      final days = _toInt(r['pin_days']);
      title = '🎉 Congratulations!';
      subtitle = 'You won a $days-day ${_formatScope(scope)} boost coupon!';
      icon = Icons.card_giftcard;
      iconColor = Colors.green;
    } else if (type == 'airtime_points') {
      final p = _toInt(r['points']);
      title = '🎉 Congratulations!';
      subtitle = 'You gained $p airtime points!';
      icon = Icons.stars;
      iconColor = Colors.amber;
    } else {
      title = 'Keep Going!';
      subtitle = 'Reward claimed! Check your rewards.';
      icon = Icons.trending_up;
      iconColor = Colors.orange;
    }

    return _wrap(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(),
          _iconBubble(icon, iconColor),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey[600]), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          _milestoneStrip(),
          if (milestoneProgress.isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoBox(milestoneProgress),
          ],
          if (loopHintText.isNotEmpty) ...[
            const SizedBox(height: 10),
            _loopBox(loopHintText),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('Spins left', '$spinsLeft', Icons.casino),
              _stat('Qualified', '$qualifiedCount', Icons.checklist),
              _stat('Points', '$points', Icons.attach_money),
            ],
          ),
          const SizedBox(height: 16),
          _goRewardsButton(),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (spinsLeft > 0) {
                  setState(() {
                    _data['spins'] = spinsLeft;
                    _spinResp = null;
                  });
                } else {
                  Navigator.of(context).pop();
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                spinsLeft > 0 ? 'Spin again' : 'Close',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardMode(BuildContext context, Map<String, dynamic> reward) {
    final typeRaw = (reward['result_type'] ?? '').toString();
    final type = typeRaw == 'featured' ? 'boost_coupon' : typeRaw;

    String title;
    String subtitle;
    IconData icon;
    Color iconColor;

    if (type == 'boost_coupon') {
      final scope = reward['pin_scope']?.toString() ?? 'unknown';
      final days = _toInt(reward['pin_days']);
      title = '🎉 Congratulations!';
      subtitle = 'You won a $days-day ${_formatScope(scope)} boost coupon!';
      icon = Icons.card_giftcard;
      iconColor = Colors.green;
    } else if (type == 'airtime_points') {
      final earned = _toInt(reward['points']);
      title = '🎉 Congratulations!';
      subtitle = 'You gained $earned airtime points!';
      icon = Icons.stars;
      iconColor = Colors.amber;
    } else {
      title = 'Reward Received';
      subtitle = 'Check your rewards page';
      icon = Icons.check_circle_outline;
      iconColor = Colors.blue;
    }

    return _wrap(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(),
          _iconBubble(icon, iconColor),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey[600]), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          _milestoneStrip(),
          if (milestoneProgress.isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoBox(milestoneProgress),
          ],
          if (loopHintText.isNotEmpty) ...[
            const SizedBox(height: 10),
            _loopBox(loopHintText),
          ],
          const SizedBox(height: 16),
          _goRewardsButton(),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Close', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressMode(BuildContext context) {
    return _wrap(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(),
          _iconBubble(Icons.trending_up, Colors.orange),
          const SizedBox(height: 12),
          const Text('Keep Going!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            milestoneProgress.isNotEmpty
                ? milestoneProgress
                : "No reward this time, but you're making progress!",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          _milestoneStrip(),
          if (loopHintText.isNotEmpty) ...[
            const SizedBox(height: 12),
            _loopBox(loopHintText),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('Qualified', '$qualifiedCount', Icons.checklist),
              _stat('Points', '$points', Icons.attach_money),
              _stat('Spins', '$spins', Icons.casino),
            ],
          ),
          const SizedBox(height: 16),
          _goRewardsButton(),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Close', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

// ✅ 转盘项目数据模型
class _WheelItem {
  final String mainText;
  final String subText;

  _WheelItem({
    required this.mainText,
    required this.subText,
  });
}
