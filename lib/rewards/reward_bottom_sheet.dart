import 'dart:math';

import 'package:flutter/material.dart';
import 'package:swaply/services/reward_after_publish.dart';
import 'package:uuid/uuid.dart';

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
  Map<String, dynamic>? _spinResp; // 保存 spin() 的返回，用于展示结果页

  late final AnimationController _ctl;
  late final Animation<double> _anim;

  double _turnsTarget = 0; // 本次转到的圈数（目标）
  double _turnsFrom = 0; // 上一次结束时的位置（起点）
  double _turnsNow = 0; // 动画中间态

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
  }

  @override
  void dispose() {
    _ctl.dispose();
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

  String get milestoneProgress => (_data['milestone_progress'] ?? '').toString();

  Map<String, dynamic>? get reward =>
      _data['reward'] is Map ? Map<String, dynamic>.from(_data['reward'] as Map) : null;

  List<Map<String, dynamic>> get pool {
    final raw = _data['pool'];
    if (raw is List) {
      return raw.map((e) {
        if (e is Map) return Map<String, dynamic>.from(e);
        return <String, dynamic>{};
      }).where((e) => e.isNotEmpty).toList();
    }
    return [];
  }

  // ✅ Loop spin progress fields (from backend)
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
    // ✅ 优先使用后端返回的文案（便于后端统一口径/国际化）
    final backendText =
    (_data['spin_loop_progress_text'] ?? '').toString().trim();
    if (backendText.isNotEmpty) return backendText;

    // Fallback：沿用你现在的前端计算逻辑
    if (!hasLoopInfo) return '';
    return 'Next loop spin in $loopRemaining listings (at #$loopNextAt)';
  }

  bool get canSpin =>
      ok && spins > 0 && !_spinning && (widget.listingId?.isNotEmpty ?? false);

  String _formatScope(String scope) {
    const names = {'category': 'Category', 'search': 'Search', 'trending': 'Trending'};
    return names[scope.toLowerCase()] ?? scope;
  }

  String _probOf(Map<String, dynamic> item) {
    final total = pool.fold<int>(0, (s, x) => s + _toInt(x['weight']));
    if (total <= 0) return '—';
    final w = _toInt(item['weight']);
    final p = (w / total) * 100;
    return '${p.toStringAsFixed(1)}%';
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
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

    // 先让动画开始转（视觉丝滑）
    final extra = 4 + Random().nextInt(4) + Random().nextDouble();
    _turnsTarget = _turnsFrom + extra;
    _ctl
      ..reset()
      ..forward();

    try {
      final resp = await RewardAfterPublish.I.spin(
        requestId: const Uuid().v4(),
        campaignCode: widget.campaignCode,
        listingId: widget.listingId,
      );

      // 等动画结束再显示结果（避免瞬间停住）
      if (_ctl.status != AnimationStatus.completed) {
        await _ctl.forward().catchError((_) {});
      }
      if (!mounted) return;

      final map = _asMap(resp);

      if (map['ok'] == true) {
        if (map.containsKey('spins_left')) {
          _data['spins'] = _toInt(map['spins_left']);
        }
        if (map.containsKey('reward')) {
          _data['reward'] = map['reward'];
        }
        if (map.containsKey('airtime_points')) {
          _data['airtime_points'] = _toInt(map['airtime_points']);
        }
        if (map.containsKey('qualified_count')) {
          _data['qualified_count'] = _toInt(map['qualified_count']);
        }

        // ✅ 如果后端把 loop 字段也一起回了，顺手同步（兼容未来）
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

  // -------------------- UI Shell --------------------

  Widget _wrap(Widget child) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: child,
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

  // ✅ 新增：循环 spin 专用提示（更贴合语义）
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

  Widget _stat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 22, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  // -------------------- Build --------------------

  @override
  Widget build(BuildContext context) {
    if (!ok) return _buildError(context);

    if (_spinResp != null) return _buildSpinResult(context, _spinResp!);

    if (spins > 0) return _buildSpinMode(context);

    if (reward != null) return _buildRewardMode(context, reward!);

    return _buildProgressMode(context);
  }

  // -------------------- Modes --------------------

  Widget _buildError(BuildContext context) {
    final subtitle =
        _data['error']?.toString() ?? _data['reason']?.toString() ?? 'Unknown error';

    return _wrap(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(),
          _iconBubble(Icons.error_outline, Colors.red),
          const SizedBox(height: 12),
          const Text(
            'Reward Failed',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Close',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
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
                child: Text(
                  '🎰 Reward Center',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              _pill('Spins: $spins'),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: _turnsNow * 2 * pi,
                  child: _wheelFace(),
                ),
                Positioned(
                  top: 8,
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: 44,
                    color: Colors.red[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Qualified: $qualifiedCount • Points: $points',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (milestoneProgress.isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoBox(milestoneProgress),
          ],
          // ✅ 新增：循环 spin 进度提示
          if (loopHintText.isNotEmpty) ...[
            const SizedBox(height: 10),
            _loopBox(loopHintText),
          ],
          const SizedBox(height: 12),
          _poolPanel(),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _spinning
                  ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Text(
                'SPIN NOW',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wheelFace() {
    final items = pool.isNotEmpty
        ? pool
        : const [
      {'title': 'Airtime +5'},
      {'title': 'Boost'},
      {'title': 'None'},
      {'title': 'Airtime +10'},
    ];

    final display = items.take(8).toList();
    final n = display.length;

    return Container(
      width: 170,
      height: 170,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade300, width: 2),
        color: Colors.grey.shade50,
      ),
      child: Stack(
        children: List.generate(n, (i) {
          final angle = (2 * pi / n) * i;
          final title = (display[i]['title'] ?? 'Reward').toString();
          return Transform.rotate(
            angle: angle,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _poolPanel() {
    if (pool.isEmpty) return const SizedBox.shrink();

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 6, bottom: 6),
      title: const Text(
        'Prize Pool & Probability',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      children: pool.take(12).map((it) {
        final title = (it['title'] ?? it['id'] ?? 'Reward').toString();
        final prob = _probOf(it);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 12))),
              Text(prob, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSpinResult(BuildContext context, Map<String, dynamic> resp) {
    if (resp['ok'] != true) {
      final reason =
          resp['reason']?.toString() ?? resp['error']?.toString() ?? 'Spin failed';

      return _wrap(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handle(),
            _iconBubble(Icons.warning_amber_rounded, Colors.orange),
            const SizedBox(height: 12),
            const Text(
              'Spin Failed',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => setState(() => _spinResp = null),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final spinsLeft = _toInt(resp['spins_left']);
    final r = resp['reward'] is Map ? Map<String, dynamic>.from(resp['reward'] as Map) : <String, dynamic>{};
    final type = r['result_type']?.toString();

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
      subtitle = 'No reward this time. Try again!';
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
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          // ✅ 结果页也显示 loop 进度（更清楚）
          if (loopHintText.isNotEmpty) ...[
            const SizedBox(height: 12),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
    final type = reward['result_type']?.toString();

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
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          if (milestoneProgress.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoBox(milestoneProgress),
          ],
          // ✅ Reward 模式也显示 loop 进度
          if (loopHintText.isNotEmpty) ...[
            const SizedBox(height: 10),
            _loopBox(loopHintText),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Close',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
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
          const Text(
            'Keep Going!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            milestoneProgress.isNotEmpty
                ? milestoneProgress
                : "No reward this time, but you're making progress!",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          // ✅ Progress 模式也显示 loop 进度
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Close',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
