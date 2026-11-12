package com.pianoforparkinson.piano_practice.accounts

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.tencent.mm.opensdk.modelbase.BaseResp
import com.tencent.mm.opensdk.modelmsg.SendAuth
import com.tencent.mm.opensdk.openapi.IWXAPI
import com.tencent.mm.opensdk.openapi.IWXAPIEventHandler
import com.tencent.mm.opensdk.openapi.WXAPIFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Initialized only by an explicit user login/bind action, never at app startup. */
object WechatLoginBridge {
    private var api: IWXAPI? = null
    private var pending: MethodChannel.Result? = null
    private var expectedState: String? = null
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { fail("WX_TIMEOUT") }

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "piano_companion/wechat_login/v1").setMethodCallHandler { call, result ->
            if (call.method == "cancel") {
                if (expectedState == call.argument<String>("state")) fail("WX_CANCELLED")
                result.success(null); return@setMethodCallHandler
            }
            if (call.method != "authorize") { result.notImplemented(); return@setMethodCallHandler }
            if (pending != null) { result.error("WX_BUSY", "Authorization is pending", null); return@setMethodCallHandler }
            val appId = call.argument<String>("app_id").orEmpty()
            val state = call.argument<String>("state").orEmpty()
            if (!appId.matches(Regex("^wx[A-Za-z0-9]{16}$")) || state.length !in 32..128) {
                result.error("WX_CONFIG", "Authorization unavailable", null); return@setMethodCallHandler
            }
            try {
                api?.detach()
                val client = WXAPIFactory.createWXAPI(context.applicationContext, appId, true)
                api = client
                if (!client.isWXAppInstalled) {
                    result.error("WX_NOT_INSTALLED", "WeChat is not installed", null); return@setMethodCallHandler
                }
                if (!client.registerApp(appId)) {
                    result.error("WX_CONFIG", "Authorization unavailable", null); return@setMethodCallHandler
                }
                pending = result
                expectedState = state
                handler.postDelayed(timeout, 120000)
                val request = SendAuth.Req().apply { scope = "snsapi_userinfo"; this.state = state }
                if (!client.sendReq(request)) fail("WX_SEND_FAILED")
            } catch (_: Exception) {
                if (pending != null) fail("WX_FAILED") else result.error("WX_FAILED", "Authorization failed", null)
            }
        }
    }

    fun handle(intent: Intent, callbacks: IWXAPIEventHandler) {
        try { api?.handleIntent(intent, callbacks) } catch (_: Exception) { fail("WX_FAILED") }
    }

    fun receive(response: BaseResp) {
        if (pending == null || response !is SendAuth.Resp) return
        when (response.errCode) {
            BaseResp.ErrCode.ERR_USER_CANCEL -> fail("WX_CANCELLED")
            BaseResp.ErrCode.ERR_AUTH_DENIED -> fail("WX_DENIED")
            BaseResp.ErrCode.ERR_OK -> {
                if (response.state != expectedState || response.code.isNullOrBlank()) { fail("WX_STATE"); return }
                val result = pending
                pending = null
                handler.removeCallbacks(timeout)
                expectedState = null
                result?.success(mapOf("code" to response.code, "state" to response.state))
            }
            else -> fail("WX_FAILED")
        }
    }

    private fun fail(code: String) {
        val result = pending
        pending = null
        expectedState = null
        handler.removeCallbacks(timeout)
        result?.error(code, "WeChat authorization did not complete", null)
    }
}
