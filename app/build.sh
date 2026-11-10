#!/bin/bash
# Build Hermes Deck - panel kendali stack Hermes (tanpa Gradle, pola PassVault)
set -e
export JAVA_HOME=~/jdk/jdk-17.0.20.1+1
export PATH=$JAVA_HOME/bin:~/kotlin/bin:$PATH
export ANDROID_HOME=~/android-sdk

PROJECT=~/workspace/hermes-deck
BUILD=/tmp/hd-build
ANDROID_JAR=$ANDROID_HOME/platforms/android-34/android.jar
[ ! -f "$ANDROID_JAR" ] && ANDROID_JAR=$ANDROID_HOME/platforms/android-36/android.jar
AAPT=$ANDROID_HOME/build-tools/36.0.0/aapt2
D8=$ANDROID_HOME/build-tools/36.0.0/d8
ZIPALIGN=$ANDROID_HOME/build-tools/36.0.0/zipalign
APKSIGNER=$ANDROID_HOME/build-tools/36.0.0/apksigner

echo "=== [1/6] Prepare ==="
rm -rf $BUILD; mkdir -p $BUILD/{classes,dex,gen,res}

echo "=== [2/6] Compile Kotlin ==="
kotlinc $PROJECT/src/com/hiroki/hermesdeck/*.kt \
  -cp $ANDROID_JAR -d $BUILD/classes 2>&1 | grep -v "^warning:" | head -30

echo "=== [3/6] AAPT2 compile resources ==="
$AAPT compile --dir $PROJECT/res -o $BUILD/res.zip 2>&1 | head -5

echo "=== [4/6] AAPT2 link ==="
$AAPT link -o $BUILD/app.apk \
  -I $ANDROID_JAR \
  --manifest $PROJECT/AndroidManifest.xml \
  --java $BUILD/gen \
  -A $PROJECT/assets \
  $BUILD/res.zip \
  --min-sdk-version 26 --target-sdk-version 34 2>&1 | head -10

echo "=== [5/6] D8 dex ==="
KOTLIN_STDLIB=~/kotlin/lib/kotlin-stdlib.jar
mkdir -p $BUILD/stdlib
cd $BUILD/stdlib && unzip -q -o $KOTLIN_STDLIB && cd ..
$D8 --lib $ANDROID_JAR --output $BUILD/dex \
  $(find $BUILD/classes -name "*.class") \
  $(find $BUILD/stdlib -name "*.class" | grep -v "META-INF") 2>&1 | head -5
cd $BUILD
unzip -q -o app.apk -d apkout
cp dex/classes.dex apkout/
# Fix: resources.arsc MUST be STORED (uncompressed) for Android R+
cd apkout
python3 << 'PYEOF'
import zipfile, os
with zipfile.ZipFile('../unsigned.apk', 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk('.'):
        for f in files:
            p = os.path.join(root, f)
            arc = os.path.relpath(p, '.')
            if arc == 'resources.arsc' or arc.endswith('.so'):
                z.write(p, arc, compress_type=zipfile.ZIP_STORED)
            else:
                z.write(p, arc, compress_type=zipfile.ZIP_DEFLATED)
PYEOF
cd ..

echo "=== [6/6] Align & sign ==="
$ZIPALIGN -f 4 unsigned.apk aligned.apk 2>&1 | head -3
KS=$PROJECT/deck.keystore
# Kata sandi keystore dibaca dari environment, TIDAK ditulis di skrip:
#   DECK_KS_PASS='kata-sandi-keystore-anda' ./build.sh
if [ -z "$DECK_KS_PASS" ]; then echo "ERROR: set DECK_KS_PASS dulu (kata sandi deck.keystore Anda)"; exit 1; fi
[ ! -f "$KS" ] && keytool -genkeypair -keystore $KS -alias deck -keyalg RSA -keysize 2048 -validity 10950 -storepass "$DECK_KS_PASS" -keypass "$DECK_KS_PASS" -dname "CN=Hermes Deck" 2>&1 | head -2
$APKSIGNER sign --ks $KS --ks-pass pass:"$DECK_KS_PASS" --key-pass pass:"$DECK_KS_PASS" --out $PROJECT/HermesDeck-v1.3.apk aligned.apk 2>&1 | head -3

echo "=== DONE ==="
ls -lh $PROJECT/HermesDeck-v1.3.apk
