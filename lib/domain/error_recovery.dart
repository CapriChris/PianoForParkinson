/// A repeated device error remains a technical interruption, never a score.
class ErrorRecovery {
  final Map<String, int> _counts = {};
  String? code;
  int get count => code == null ? 0 : _counts[code] ?? 0;
  bool get unstable => count >= 4;
  bool record(String reason) {
    if (!reason.startsWith('E_') && !reason.startsWith('INVALID_')) {
      return false;
    }
    code = reason;
    _counts[reason] = (_counts[reason] ?? 0) + 1;
    return true;
  }
}
