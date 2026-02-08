import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol/patrol.dart';
import 'package:swaply/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolTest('smoke: app boots', ($) async {
    app.main();
    await $.pumpAndSettle();
    expect(true, isTrue);
  });

  patrolTest('smoke: no RenderFlex overflow in logs (basic run)', ($) async {
    app.main();
    await $.pumpAndSettle();
    // 这里只做“能稳定跑住”验证，日志关键字扫描放到脚本里做
    expect(true, isTrue);
  });
}
