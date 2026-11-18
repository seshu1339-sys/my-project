import 'package:flutter_test/flutter_test.dart';

import 'package:ecommerce_app/domain/health_status.dart';
import 'package:ecommerce_app/services/photo_compress.dart';
import 'package:ecommerce_app/services/problem_shots.dart';
import 'package:image/image.dart' as img;

// Cost cuts part 3 (18 Nov 2026): one record per problem with its people count (100+), its last 3 examples and at most 3 screenshot
// paths in the US bucket; problem screenshots are made small on the phone.
void main() {
  test('one problem record: 100+ people, the last examples and the screenshot paths', () {
    final p = AppProblem.from('vendor~android~stuck~ab', {
      'app': 'vendor', 'platform': 'android', 'kind': 'stuck', 'message': 'Kept loading', 'count': 240, 'users': 100, 'usersMore': true,
      'examples': [
        {'version': '1.0.13', 'model': 'Redmi 9', 'userCode': 'VEN-1', 'shot': 'problems/x/1-1.jpg'},
        {'version': '1.0.12', 'model': 'Galaxy A12'},
      ],
      'shotPaths': ['problems/x/1-1.jpg', 'problems/x/2-2.jpg'],
      'lastShot': 'problems/x/2-2.jpg',
    });
    expect(p.usersMore, isTrue);
    expect(peopleText(p.users, p.usersMore), '100+ people');
    expect(p.examples, hasLength(2));
    expect(p.examples.first['userCode'], 'VEN-1');
    expect(p.screenshots, ['problems/x/1-1.jpg', 'problems/x/2-2.jpg']);
  });

  test('a record of the version before still shows its one screenshot', () {
    final p = AppProblem.from('a', {'lastShot': 'caseId123', 'users': 1});
    expect(p.screenshots, ['caseId123']);
    expect(p.usersMore, isFalse);
    expect(p.examples, isEmpty);
    expect(peopleText(1, false), '1 person');
    expect(peopleText(7, false), '7 people');
  });

  test('a problem screenshot is made under 60 KB on the phone', () {
    final big = img.Image(width: 1600, height: 1200);
    for (var y = 0; y < big.height; y++) {
      for (var x = 0; x < big.width; x++) {
        big.setPixelRgb(x, y, (x * 7 + y) % 256, (y * 13) % 256, (x ^ y) % 256);
      }
    }
    final photo = img.encodePng(big);
    final small = shrinkProblemShot(photo)!;
    expect(small.length, lessThanOrEqualTo(problemShotMaxBytes));
    expect(small[0], 0xff, reason: 'a JPEG');
  });
}
