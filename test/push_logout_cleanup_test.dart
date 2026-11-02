import 'package:flutter_test/flutter_test.dart';
import 'package:playon/core/services/push_logout_cleanup.dart';

void main() {
  for (final remoteFails in [false, true]) {
    for (final revokeFails in [false, true]) {
      test('logout cleanup remote=$remoteFails revoke=$revokeFails', () async {
        final calls = <String>[];
        final errors = <Object>[];
        await cleanUpPushOnLogout(
          removeRegistration: () async {
            calls.add('remote');
            if (remoteFails) throw StateError('offline');
          },
          revokeInstallationToken: () async {
            calls.add('revoke');
            if (revokeFails) throw StateError('unavailable');
          },
          onFailure: errors.add,
        );
        expect(calls, ['remote', 'revoke']);
        expect(errors.length, (remoteFails ? 1 : 0) + (revokeFails ? 1 : 0));
      });
    }
  }
}
