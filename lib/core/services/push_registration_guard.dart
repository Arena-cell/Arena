/// Invalidates asynchronous registration work started for a previous session.
class PushRegistrationGuard {
  int _generation = 0;
  bool _blocked = false;
  int get generation => _generation;
  bool permits(int generation) => !_blocked && generation == _generation;
  void beginLogout() {
    _blocked = true;
    _generation++;
  }

  void signedIn() {
    _blocked = false;
    _generation++;
  }
}
