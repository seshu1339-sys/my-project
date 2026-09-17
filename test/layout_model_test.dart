import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/domain/catalog.dart';
import 'package:ecommerce_app/ui/layout_settings.dart';

void main() {
  test('breakpoint widths override only the selected breakpoint', () {
    const entry = Entry('section_search', {
      'width': 500,
      'mobileWidth': 280,
      'tabletWidth': 480,
      'desktopWidth': 800,
    });
    expect(ComponentLayout(entry, 390).width(366), 280);
    expect(ComponentLayout(entry, 768).width(700), 480);
    expect(ComponentLayout(entry, 1440).width(1200), 800);
    expect(ComponentLayout(entry, 1440).width(400), 400);
  });
  test(
    'automatic dimensions fill available space within configured bounds',
    () {
      const entry = Entry('section_search', {'minWidth': 240, 'maxWidth': 900});
      expect(ComponentLayout(entry, 1920).width(1400), 900);
      expect(ComponentLayout(entry, 390).width(300), 300);
      expect(ComponentLayout(entry, 1920).height(56, floor: 48), 56);
    },
  );
}
