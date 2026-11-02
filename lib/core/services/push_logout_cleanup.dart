/// Independent best-effort cleanup: a failed server request must never skip
/// revoking the installation token. Offline revocation is not guaranteed.
Future<void> cleanUpPushOnLogout({
  required Future<void> Function() removeRegistration,
  required Future<void> Function() revokeInstallationToken,
  required void Function(Object) onFailure,
}) async {
  try {
    await removeRegistration();
  } on Object catch (error) {
    onFailure(error);
  }
  try {
    await revokeInstallationToken();
  } on Object catch (error) {
    onFailure(error);
  }
}
