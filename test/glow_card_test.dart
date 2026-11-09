import 'package:fitness_mobile/core/palette.dart';
import 'package:fitness_mobile/core/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester) => tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: GlowCard(child: SizedBox(width: 200, height: 100))),
      ),
    ),
  );

  BoxDecoration decoration(WidgetTester tester) {
    final box = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    return box.decoration! as BoxDecoration;
  }

  double lift(WidgetTester tester) =>
      tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).transform!.getTranslation().y;

  testWidgets('at rest the card is dark grey with a grey border', (tester) async {
    await pumpCard(tester);
    expect(decoration(tester).color, Hxvy.card);
    expect((decoration(tester).border! as Border).top.color, Hxvy.border);
    expect(lift(tester), 0);
  });

  testWidgets('pressing lifts it 5px with a white border, letting go puts it back', (tester) async {
    await pumpCard(tester);

    final finger = await tester.startGesture(tester.getCenter(find.byType(GlowCard)));
    await tester.pumpAndSettle();
    expect(lift(tester), -5);
    expect(decoration(tester).color, Hxvy.cardActive);
    expect((decoration(tester).border! as Border).top.color, Hxvy.accent);

    await finger.up();
    await tester.pumpAndSettle();
    expect(lift(tester), 0);
    expect(decoration(tester).color, Hxvy.card);
  });

  testWidgets('a mouse hovering over it does the same', (tester) async {
    await pumpCard(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(GlowCard)));
    await tester.pumpAndSettle();
    expect(lift(tester), -5);

    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(lift(tester), 0);
  });
}
