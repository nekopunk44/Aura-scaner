package com.aurascanner.app

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (не FlutterActivity) требуется плагином local_auth
// для показа системного биометрического диалога на Android.
class MainActivity : FlutterFragmentActivity()
