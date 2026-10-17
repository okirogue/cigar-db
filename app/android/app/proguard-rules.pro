# jnigen 기반 플러그인(shared_preferences_android 등)이 Kotlin suspend 함수를 이름으로 찾는다.
# R8 이 kotlin.coroutines.Continuation 을 난독화하면 메서드 시그니처가 안 맞아
# "NoSuchMethodError: no non-static method ...getAll(...Continuation;)" 로 터짐 (dart-lang/native#3732).
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
