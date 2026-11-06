const accountPasswordRequirement = '密码须为8-16位';

String? validateNewAccountPassword(String? value, {String label = '密码'}) {
  if (value == null || value.isEmpty) return '请输入$label';
  final length = value.runes.length;
  return length < 8 || length > 16 ? accountPasswordRequirement : null;
}
