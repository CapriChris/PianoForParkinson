import 'package:flutter/services.dart';

class WechatLoginError implements Exception {
  const WechatLoginError(this.message);
  final String message;
}

class WechatLogin {
  static const channel = MethodChannel('piano_companion/wechat_login/v1');

  static Future<void> cancel(String state) =>
      channel.invokeMethod<void>('cancel', {'state': state});

  static Future<String> authorize(String appId, String state) async {
    try {
      final result = await channel.invokeMapMethod<String, dynamic>(
        'authorize',
        {'app_id': appId, 'state': state},
      );
      if (result?['state'] != state ||
          result?['code'] is! String ||
          (result!['code'] as String).isEmpty) {
        throw const WechatLoginError('微信授权校验失败，请重试。');
      }
      return result['code'] as String;
    } on MissingPluginException {
      throw const WechatLoginError('当前版本暂不支持微信登录，请使用账号密码登录。');
    } on PlatformException catch (error) {
      throw WechatLoginError(switch (error.code) {
        'WX_NOT_INSTALLED' => '请先安装微信并登录后重试。',
        'WX_CANCELLED' => '已取消微信授权。',
        'WX_DENIED' => '未获得微信授权，请重试或使用其他登录方式。',
        'WX_TIMEOUT' => '微信授权超时，请重新尝试。',
        'WX_BUSY' => '微信授权正在进行，请稍候。',
        _ => '微信授权失败，请重试或使用其他登录方式。',
      });
    }
  }
}
