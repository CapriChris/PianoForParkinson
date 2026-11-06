import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/accounts/password_rules.dart';

void main() {
  test(
    'empty password prompts entry, other invalid lengths explain the rule',
    () {
      expect(validateNewAccountPassword(null), '请输入密码');
      expect(validateNewAccountPassword(''), '请输入密码');
      expect(validateNewAccountPassword('', label: '新密码'), '请输入新密码');
      expect(validateNewAccountPassword('1234567'), accountPasswordRequirement);
      expect(validateNewAccountPassword('1' * 17), accountPasswordRequirement);
    },
  );
  test('8 and 16 character passwords are accepted including Unicode', () {
    expect(validateNewAccountPassword('1' * 8), isNull);
    expect(validateNewAccountPassword('1' * 16), isNull);
    expect(validateNewAccountPassword('🎹' * 16), isNull);
    expect(validateNewAccountPassword('🎹' * 17), accountPasswordRequirement);
  });
}
