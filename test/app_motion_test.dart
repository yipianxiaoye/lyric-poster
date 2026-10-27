import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_poster/app_motion.dart';

void main() {
  Widget scene({
    required Object identity,
    bool reduceMotion = false,
    String label = '当前内容',
    Key? contentKey,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: AppMotion(
        identity: identity,
        child: SizedBox(key: contentKey, child: Text(label)),
      ),
    ),
  );

  Finder fadeInMotion() => find.descendant(
    of: find.byType(AppMotion),
    matching: find.byType(FadeTransition),
  );

  double opacity(WidgetTester tester) =>
      tester.widget<FadeTransition>(fadeInMotion()).opacity.value;

  testWidgets('首次显示清晰，切换只保留当前内容和一个GlobalKey实例', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(scene(identity: 0, contentKey: key));
    expect(opacity(tester), 1);
    expect(find.text('当前内容'), findsOneWidget);
    final content = key.currentContext;

    await tester.pumpWidget(scene(identity: 1, label: '新内容', contentKey: key));
    expect(find.text('当前内容'), findsNothing);
    expect(find.text('新内容'), findsOneWidget);
    expect(key.currentContext, same(content));
    expect(opacity(tester), lessThan(1));
    await tester.pump(const Duration(milliseconds: 80));
    expect(opacity(tester), greaterThan(.84));
    expect(opacity(tester), lessThan(1));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
  });

  testWidgets('实时编辑在相同identity下不会重新淡出或重启动画', (tester) async {
    await tester.pumpWidget(scene(identity: 0));
    await tester.pumpWidget(scene(identity: 1));
    await tester.pump(const Duration(milliseconds: 80));
    final inProgress = opacity(tester);
    await tester.pumpWidget(scene(identity: 1, label: '改过的歌词'));
    expect(opacity(tester), inProgress);
    expect(find.text('改过的歌词'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 80));
    expect(opacity(tester), greaterThan(inProgress));
    await tester.pumpAndSettle();
    await tester.pumpWidget(scene(identity: 1, label: '继续拖动背景'));
    expect(opacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('系统减少动画在切换和动画途中都立即显示最终状态', (tester) async {
    await tester.pumpWidget(scene(identity: 0, reduceMotion: true));
    await tester.pumpWidget(scene(identity: 1, reduceMotion: true));
    expect(opacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(scene(identity: 1));
    await tester.pumpWidget(scene(identity: 2));
    await tester.pump(const Duration(milliseconds: 35));
    expect(opacity(tester), lessThan(1));
    await tester.pumpWidget(scene(identity: 2, reduceMotion: true));
    expect(opacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
