# google_mlkit_text_recognition references every script's recognizer, but the
# app only ships the Latin one. Without these, R8 fails the release build on
# the missing Chinese, Devanagari, Japanese and Korean classes.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
