import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SystemNotificationDetailPage extends StatelessWidget {
  final Map<String, dynamic> notification;

  const SystemNotificationDetailPage({
    super.key,
    required this.notification,
  });

  @override
  Widget build(BuildContext context) {
    final title = notification['title'] ?? 'System Notification';
    final message = notification['message'] ?? '';
    final createdAt = notification['created_at'];

    String dateStr = '';
    if (createdAt != null) {
      try {
        final date = DateTime.parse(createdAt).toLocal();
        dateStr = DateFormat('yyyy-MM-dd HH:mm').format(date);
      } catch (_) {}
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图标与标题栏
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.notifications_active, color: Colors.blue.shade700, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 时间戳
            if (dateStr.isNotEmpty)
              Text(
                dateStr,
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
              
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Divider(),
            ),
            
            // 正文内容
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                height: 1.6,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}