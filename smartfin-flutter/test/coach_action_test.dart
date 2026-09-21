import 'package:flutter_test/flutter_test.dart';

import 'package:smart_fin/features/coach/data/coach_repository_impl.dart';

void main() {
  test('reads both kinds of coach write with their labels', () {
    final actions = CoachAction.listFrom([
      {
        'status': 'success',
        'action': 'add_transaction',
        'id': '66f0c0ffee0000000000abcd',
        'amount': 120,
        'label': 'Added ฿120 · 7-Eleven',
      },
      {
        'status': 'success',
        'action': 'update_budget_limit',
        'budget_limit': 15000,
        'label': 'Budget set to ฿15,000',
      },
    ]);

    expect(actions, hasLength(2));
    expect(actions[0].action, 'add_transaction');
    expect(actions[0].id, '66f0c0ffee0000000000abcd');
    expect(actions[0].label, 'Added ฿120 · 7-Eleven');
    expect(actions[1].action, 'update_budget_limit');
    expect(actions[1].id, isNull);
    expect(actions[1].label, 'Budget set to ฿15,000');
  });

  test('skips records with no label and tolerates a missing list', () {
    expect(CoachAction.listFrom(null), isEmpty);
    expect(CoachAction.listFrom('nope'), isEmpty);
    expect(
      CoachAction.listFrom([
        {'action': 'add_transaction', 'id': 'x'},
        {'action': 'add_transaction', 'label': ''},
        'not a map',
      ]),
      isEmpty,
    );
  });
}
