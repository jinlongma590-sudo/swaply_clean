// lib/pages/offer_detail_page.dart
//
// OfferDetailPage —— 仅接收 offerId（与 /offer-detail 路由一致）
// ✅ 性能优化：并行加载 + 骨架屏 + 缓存支持
// ✅ [Offer消息修复] 在offer详情页显示buyer message
// - 顶部栏统一 Facebook Blue 实色
// - 空 offerId 兜底提示并返回
// - 加强消息订阅/释放与已读上报
// - 阻止被屏蔽/屏蔽对方时发送消息
//
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/models/offer.dart';
import 'package:swaply/services/message_service.dart';
import 'package:swaply/services/offer_service.dart';
import 'package:swaply/services/verification_guard.dart';
import 'package:swaply/services/offer_detail_cache.dart';

class OfferDetailPage extends StatefulWidget {
  final String offerId;

  const OfferDetailPage({
    super.key,
    required this.offerId,
  });

  @override
  State<OfferDetailPage> createState() => _OfferDetailPageState();
}

class _OfferDetailPageState extends State<OfferDetailPage> {
  static const Color _fbBlue = Color(0xFF1877F2);

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  Map<String, dynamic>? _offerDetails;

  List<Map<String, dynamic>> _messages = [];
  bool _isLoadingMessages = true;
  bool _isSendingMessage = false;

  String? _currentUserId;
  RealtimeChannel? _messageChannel;

  bool _iBlockedOther = false;
  bool _otherBlockedMe = false;
  bool get _blockedEitherWay => _iBlockedOther || _otherBlockedMe;

  bool _invalid = false;

  @override
  void initState() {
    super.initState();

    final id = widget.offerId.trim();
    if (id.isEmpty) {
      _invalid = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSnackBar('Invalid offer link', isError: true);
        Navigator.of(context).maybePop();
      });
      return;
    }

    _currentUserId = Supabase.instance.client.auth.currentUser?.id;

    _loadAllDataInParallel();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _unsubscribeFromMessages();

    OfferDetailCache.clear(widget.offerId);

    super.dispose();
  }

  Future<void> _loadAllDataInParallel() async {
    final futures = <Future>[
      _loadOfferDetailsOptimized(),
      _loadMessagesOptimized(),
    ];
    await Future.wait(futures, eagerError: false);
  }

  Future<void> _loadOfferDetailsOptimized() async {
    final cached = OfferDetailCache.getDetails(widget.offerId);
    if (cached != null && mounted) {
      setState(() => _offerDetails = cached);
    }

    try {
      final details = await OfferService.getOfferDetails(widget.offerId);
      if (details != null && mounted) {
        setState(() => _offerDetails = details);
        _refreshBlockStatus();
      }
    } catch (_) {}
  }

  Future<void> _loadMessagesOptimized() async {
    final cached = OfferDetailCache.getMessages(widget.offerId);
    if (cached != null && mounted) {
      setState(() {
        _messages = cached;
        _isLoadingMessages = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } else {
      if (mounted) setState(() => _isLoadingMessages = true);
    }

    try {
      final messages = await MessageService.getOfferMessages(
        offerId: widget.offerId,
      );
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _isLoadingMessages = false;
      });

      if (_currentUserId != null) {
        MessageService.markMessagesAsRead(
          offerId: widget.offerId,
          receiverId: _currentUserId!,
        ).catchError((_) {});
      }

      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      if (mounted) setState(() => _isLoadingMessages = false);
    }
  }

  void _subscribeToMessages() {
    if (_messageChannel != null) return;
    _messageChannel = MessageService.subscribeToOfferMessages(
      offerId: widget.offerId,
      onMessageReceived: (message) {
        if (!mounted) return;
        setState(() => _messages.add(message));
        if (message['receiver_id'] == _currentUserId) {
          MessageService.markMessagesAsRead(
            offerId: widget.offerId,
            receiverId: _currentUserId!,
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      },
    );
  }

  void _unsubscribeFromMessages() {
    final ch = _messageChannel;
    if (ch != null) {
      MessageService.unsubscribeFromMessages(ch);
      _messageChannel = null;
    }
  }

  String? _getPeerId() {
    if (_offerDetails == null || _currentUserId == null) return null;
    final buyerId = _offerDetails!['buyer_id'] as String?;
    final sellerId = _offerDetails!['seller_id'] as String?;
    if (buyerId == null || sellerId == null) return null;
    return _currentUserId == buyerId ? sellerId : buyerId;
  }

  Future<void> _refreshBlockStatus() async {
    try {
      final me = _currentUserId;
      final peer = _getPeerId();
      if (me == null || peer == null) return;
      final status = await OfferService.getBlockStatusBetween(a: me, b: peer);
      if (!mounted) return;
      setState(() {
        _iBlockedOther = status.iBlockedOther;
        _otherBlockedMe = status.otherBlockedMe;
      });
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    _inputFocus.unfocus();

    final allowed = await VerificationGuard.ensureVerifiedOrPrompt(
      context,
      feature: AppFeature.makeOffer,
    );
    if (!allowed) return;

    if (_blockedEitherWay) {
      _showSnackBar(
        _otherBlockedMe
            ? 'You can\'t send messages because this user has blocked you.'
            : 'You blocked this user. Unblock to send messages.',
        isError: true,
      );
      return;
    }

    final message = _messageController.text.trim();
    if (message.isEmpty || _isSendingMessage) return;
    if (_currentUserId == null || _offerDetails == null) return;

    setState(() => _isSendingMessage = true);
    try {
      final buyerId = _offerDetails!['buyer_id'];
      final sellerId = _offerDetails!['seller_id'];
      final receiverId = _currentUserId == buyerId ? sellerId : buyerId;

      final result = await MessageService.sendMessage(
        offerId: widget.offerId,
        receiverId: receiverId,
        message: message,
      );
      if (result != null) _messageController.clear();
    } catch (_) {
      _showSnackBar('发送消息时出现错误', isError: true);
    } finally {
      if (mounted) setState(() => _isSendingMessage = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_rounded,
              color: Colors.white,
              size: 16.sp,
            ),
            SizedBox(width: 8.w),
            Expanded(child: Text(message, style: TextStyle(fontSize: 13.sp))),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        margin: EdgeInsets.all(12.w),
      ),
    );
  }

  Widget _buildOfferInfo() {
    if (_offerDetails == null) {
      return Card(
        margin: EdgeInsets.all(12.w),
        child: SizedBox(
          height: 120.h,
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 20.h,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
                SizedBox(height: 12.h),
                Container(
                  height: 32.h,
                  width: 120.w,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Container(
                      height: 16.h,
                      width: 80.w,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      height: 16.h,
                      width: 60.w,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final listing = _offerDetails!['listings'] as Map<String, dynamic>? ?? {};
    final offerAmount = _offerDetails!['offer_amount']?.toString() ?? '0';
    final originalPrice = listing['price']?.toString() ?? '0';
    final title = listing['title']?.toString() ?? 'Unknown Item';
    final status = _offerDetails!['status']?.toString() ?? 'pending';
    final offerStatus = OfferStatus.fromString(status);

    final offer = double.tryParse(offerAmount) ?? 0;
    final original = double.tryParse(originalPrice.replaceAll('\$', '')) ?? 0;
    final percentage = original > 0 ? ((offer / original) * 100).round() : 0;

    // ✅ [Offer消息修复] 获取buyer message
    final buyerMessage = _offerDetails!['message']?.toString();
    final hasBuyerMessage = buyerMessage != null && buyerMessage.isNotEmpty;

    return Card(
      margin: EdgeInsets.all(12.w),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: Color(offerStatus.color).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: Color(offerStatus.color).withOpacity(0.3),
                      width: 1.w,
                    ),
                  ),
                  child: Text(
                    offerStatus.displayText,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: Color(offerStatus.color),
                    ),
                  ),
                ),
                SizedBox(width: 6.w),
                _buildMoreMenu(),
              ],
            ),
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Offer Amount',
                          style: TextStyle(
                              fontSize: 11.sp, color: Colors.grey.shade600)),
                      Text('\$$offerAmount',
                          style: TextStyle(
                              fontSize: 20.sp,
                              fontWeight: FontWeight.bold,
                              color: _fbBlue)),
                    ],
                  ),
                  if (original > 0)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Original Price',
                            style: TextStyle(
                                fontSize: 11.sp, color: Colors.grey.shade600)),
                        Row(
                          children: [
                            Text('\$$original',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  color: Colors.grey.shade600,
                                  decoration: TextDecoration.lineThrough,
                                )),
                            SizedBox(width: 8.w),
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 6.w, vertical: 2.h),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: Text('$percentage%',
                                  style: TextStyle(
                                      fontSize: 10.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade700)),
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // ✅ [Offer消息修复] 显示buyer message卡片
            if (hasBuyerMessage) ...[
              SizedBox(height: 12.h),
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.message,
                            size: 14.sp, color: Colors.blue.shade700),
                        SizedBox(width: 6.w),
                        Text(
                          'Buyer\'s Message',
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      buyerMessage,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.grey[800],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMoreMenu() {
    final canToggleBlock = _getPeerId() != null && _currentUserId != null;
    return PopupMenuButton<int>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      onSelected: _onMenuAction,
      itemBuilder: (context) => <PopupMenuEntry<int>>[
        PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              Icon(Icons.flag_outlined, size: 18.w),
              SizedBox(width: 8.w),
              const Text('Report user'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<int>(
          enabled: canToggleBlock,
          value: 2,
          child: Row(
            children: [
              Icon(_iBlockedOther ? Icons.lock_open : Icons.block, size: 18.w),
              SizedBox(width: 8.w),
              Text(_iBlockedOther ? 'Unblock' : 'Block'),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onMenuAction(int value) async {
    switch (value) {
      case 1:
        _showReportSheet();
        break;
      case 2:
        await _toggleBlock();
        break;
    }
  }

  void _showReportSheet() {
    final peerId = _getPeerId();
    if (peerId == null) {
      _showSnackBar('Unable to report: user not found', isError: true);
      return;
    }
    String type = 'Spam';
    final TextEditingController descCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16.w,
            right: 16.w,
            top: 16.h,
            bottom: 16.h + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Text('Report user',
                  style:
                      TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
              SizedBox(height: 12.h),
              DropdownButtonFormField<String>(
                value: type,
                items: const [
                  DropdownMenuItem(value: 'Spam', child: Text('Spam')),
                  DropdownMenuItem(value: 'Scam', child: Text('Scam/Fraud')),
                  DropdownMenuItem(
                      value: 'Harassment', child: Text('Harassment/Abuse')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (v) => type = v ?? 'Spam',
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              SizedBox(height: 8.h),
              TextField(
                controller: descCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Describe the issue (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 12.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final ok = await OfferService.submitReport(
                      reportedId: peerId,
                      type: type,
                      description: descCtrl.text.trim().isEmpty
                          ? null
                          : descCtrl.text.trim(),
                      offerId: widget.offerId,
                      listingId: _offerDetails?['listing_id'] as String?,
                    );
                    Navigator.of(ctx).pop();
                    if (ok) {
                      _showSnackBar(
                          'Report submitted. Thank you for keeping the community safe.');
                    } else {
                      _showSnackBar('Failed to submit report', isError: true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _fbBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r)),
                  ),
                  child: const Text('Submit'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleBlock() async {
    final peerId = _getPeerId();
    if (peerId == null) return;
    bool ok = false;
    if (_iBlockedOther) {
      ok = await OfferService.unblockUser(blockedId: peerId);
      if (ok) _showSnackBar('Unblocked successfully');
    } else {
      ok = await OfferService.blockUser(blockedId: peerId);
      if (ok) _showSnackBar('User has been blocked');
    }
    if (ok) {
      await _refreshBlockStatus();
      setState(() {});
    } else {
      _showSnackBar('Operation failed, please try again', isError: true);
    }
  }

  Widget _buildSystemMessage(Map<String, dynamic> message) {
    final text = message['message']?.toString() ?? '';
    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.amber.shade200, width: 1.w),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.amber.shade800,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildChatMessage(Map<String, dynamic> message, bool isMyMessage) {
    final text = message['message']?.toString() ?? '';
    final createdAt = message['created_at']?.toString() ?? '';

    String timeText = 'Now';
    if (createdAt.isNotEmpty) {
      try {
        final date = DateTime.parse(createdAt);
        final now = DateTime.now();
        final d = now.difference(date);
        if (d.inMinutes < 1) {
          timeText = 'Now';
        } else if (d.inMinutes < 60) {
          timeText = '${d.inMinutes}m';
        } else if (d.inHours < 24) {
          timeText = '${d.inHours}h';
        } else {
          timeText = '${date.day}/${date.month}';
        }
      } catch (_) {}
    }

    return Align(
      alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4.h),
        child: Column(
          crossAxisAlignment:
              isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: isMyMessage ? _fbBlue : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(18.r).copyWith(
                  bottomRight: isMyMessage
                      ? Radius.circular(4.r)
                      : Radius.circular(18.r),
                  bottomLeft: isMyMessage
                      ? Radius.circular(18.r)
                      : Radius.circular(4.r),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4.r,
                    offset: Offset(0, 1.h),
                  ),
                ],
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: isMyMessage ? Colors.white : Colors.grey.shade800,
                  fontSize: 14.sp,
                  height: 1.3,
                ),
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              timeText,
              style: TextStyle(fontSize: 10.sp, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (_isLoadingMessages) {
      return Expanded(
        child: Center(
          child: CircularProgressIndicator(
            valueColor: const AlwaysStoppedAnimation<Color>(_fbBlue),
            strokeWidth: 2.5.w,
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 64.w, color: Colors.grey.shade400),
              SizedBox(height: 16.h),
              Text('No messages yet',
                  style: TextStyle(
                      fontSize: 16.sp,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500)),
              SizedBox(height: 8.h),
              Text('Start the conversation!',
                  style:
                      TextStyle(fontSize: 14.sp, color: Colors.grey.shade500)),
            ],
          ),
        ),
      );
    }

    final List<Widget> children = [];
    if (_blockedEitherWay) children.add(_buildBlockBanner());

    children.add(
      Expanded(
        child: ListView.builder(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            final m = _messages[index];
            final isMine = m['sender_id'] == _currentUserId;
            final type = m['message_type'] ?? 'text';
            if (type == 'system') return _buildSystemMessage(m);
            return _buildChatMessage(m, isMine);
          },
        ),
      ),
    );

    return Expanded(child: Column(children: children));
  }

  Widget _buildBlockBanner() {
    final text = _otherBlockedMe
        ? 'You can\'t send messages because this user has blocked you.'
        : 'You blocked this user. Unblock to continue chatting.';
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(12.w, 0, 12.w, 6.h),
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.red.shade200, width: 1.w),
      ),
      child: Row(
        children: [
          Icon(Icons.block, size: 16.w, color: Colors.red.shade700),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(text,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12.sp)),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    final disabled = _blockedEitherWay;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12.w,
        8.h,
        12.w,
        8.h,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4.r,
            offset: Offset(0, -1.h),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: disabled ? Colors.grey.shade200 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(25.r),
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _inputFocus,
                  enabled: !disabled,
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  style: TextStyle(fontSize: 14.sp),
                  decoration: InputDecoration(
                    hintText: disabled
                        ? (_otherBlockedMe
                            ? 'You are blocked by this user'
                            : 'You blocked this user')
                        : 'Type a message...',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14.sp,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 10.h,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            Opacity(
              opacity: disabled ? 0.4 : 1,
              child: IgnorePointer(
                ignoring: disabled,
                child: Container(
                  decoration: const BoxDecoration(
                    color: _fbBlue,
                    shape: BoxShape.circle,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isSendingMessage ? null : _sendMessage,
                      borderRadius: BorderRadius.circular(25.r),
                      child: SizedBox(
                        width: 50.w,
                        height: 50.h,
                        child: _isSendingMessage
                            ? Padding(
                                padding: EdgeInsets.all(12.w),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.w,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                ),
                              )
                            : Icon(Icons.send_rounded,
                                color: Colors.white, size: 24.w),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final double toolbarHeight = isIOS ? 44.0 : kToolbarHeight;

    if (_invalid) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          toolbarHeight: toolbarHeight,
          backgroundColor: _fbBlue,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text('Offer Details',
              style: TextStyle(color: Colors.white, fontSize: 18.sp)),
        ),
        body: Center(
          child: Text('Invalid offer link',
              style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade600)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: toolbarHeight,
        backgroundColor: _fbBlue,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: Colors.white, size: 20),
        title: Text(
          'Offer Details',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18.sp,
          ),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Column(
          children: [
            _buildOfferInfo(),
            _buildMessageList(),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }
}
