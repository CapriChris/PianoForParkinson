package com.pianoforparkinson.piano_practice.accounts

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.tencent.mm.opensdk.modelbase.BaseReq
import com.tencent.mm.opensdk.modelbase.BaseResp
import com.tencent.mm.opensdk.openapi.IWXAPIEventHandler
import com.pianoforparkinson.piano_practice.MainActivity

/** Reached through the applicationId.wxapi.WXEntryActivity manifest alias. */
class WechatCallbackActivity : Activity(), IWXAPIEventHandler {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WechatLoginBridge.handle(intent, this)
        returnToApp()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        WechatLoginBridge.handle(intent, this)
        returnToApp()
    }

    override fun onReq(request: BaseReq) { }
    override fun onResp(response: BaseResp) { WechatLoginBridge.receive(response) }

    private fun returnToApp() {
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        finish()
    }
}
