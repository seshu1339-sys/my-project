import 'package:flutter_test/flutter_test.dart';
import 'package:ecommerce_app/ui/service_categories.dart';

void main() {
  testWidgets(
    'loads all 30 service types from the bundled JSON, each with a matching webp filename',
    (tester) async {
      final services = await loadServiceCategories();
      expect(services, hasLength(30));
      expect(services.first.id, 'plumber');
      expect(services.last.id, 'tutor');
      expect(
        services,
        everyElement(
          predicate<ServiceCategory>((s) => s.imageFileName == '${s.id}.webp'),
        ),
      );
    },
  );
}
