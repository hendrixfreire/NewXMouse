#!/bin/bash
# Build and deploy New X Mouse with STABLE signing
# 
# Problem: Every ad-hoc build has a different cdhash, so macOS TCC revokes
# Accessibility/Input Monitoring permissions on every deploy.
#
# Solution: Sign with a self-signed certificate. TCC ties permissions to the
# certificate identity (not the cdhash), so permissions persist across rebuilds.
#
# First run: You'll be prompted to trust the certificate in Keychain Access.
# After that, permissions survive rebuilds.

set -e

CERT_NAME="New X Mouse Development"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="New X Mouse"
SCHEME="NewXMouse"
APP_PATH="/Applications/$APP_NAME.app"

# --- Step 1: Ensure signing certificate exists ---
if ! security find-identity -v -p codesigning 2>&1 | grep -q "$CERT_NAME"; then
    echo "⚠️  No trusted code signing identity found."
    echo "Creating self-signed certificate '$CERT_NAME'..."
    
    TEMP_DIR=$(mktemp -d)
    CERT_PASS="nxm2026dev"
    
    cat > "$TEMP_DIR/openssl.cnf" << EOF
[req]
default_bits = 2048
default_md = sha256
prompt = no
distinguished_name = dn
x509_extensions = v3_code

[dn]
CN = $CERT_NAME
O = NewXMouse
C = BR

[v3_code]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
    
    openssl req -x509 -newkey rsa:2048 -keyout "$TEMP_DIR/key.pem" -out "$TEMP_DIR/cert.pem" \
        -days 3650 -nodes -config "$TEMP_DIR/openssl.cnf" 2>/dev/null
    
    openssl pkcs12 -export -out "$TEMP_DIR/cert.p12" \
        -inkey "$TEMP_DIR/key.pem" -in "$TEMP_DIR/cert.pem" \
        -name "$CERT_NAME" -passout pass:"$CERT_PASS" 2>/dev/null
    
    security import "$TEMP_DIR/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
        -P "$CERT_PASS" -T /usr/bin/codesign -T /usr/bin/productsign 2>/dev/null
    
    rm -rf "$TEMP_DIR"
    
    echo ""
    echo "🔑 Certificate imported. You MUST trust it for code signing:"
    echo "   1. Keychain Access should be open — find '$CERT_NAME'"
    echo "   2. Double-click the certificate"
    echo "   3. Expand Trust → set Code Signing to 'Always Trust'"
    echo "   4. Close the window and authenticate"
    echo ""
    echo "Press Enter when done (or Ctrl+C to abort)..."
    read -r
    
    if ! security find-identity -v -p codesigning 2>&1 | grep -q "$CERT_NAME"; then
        echo "❌ Certificate still not trusted. Cannot continue."
        echo "   Try: Open Keychain Access → login → My Certificates → '$CERT_NAME'"
        echo "   → Get Info → Trust → Code Signing → Always Trust"
        exit 1
    fi
fi

echo "✅ Signing identity ready."

# --- Step 2: Build ---
echo "🔨 Building $APP_NAME..."
xcodebuild build \
    -project "$PROJECT_DIR/NewXMouse.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$PROJECT_DIR/build" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    | tail -3

BUILT_APP="$PROJECT_DIR/build/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "❌ Build failed — app not found at $BUILT_APP"
    exit 1
fi

# --- Step 3: Sign with stable identity ---
echo "🔏 Signing with '$CERT_NAME'..."
codesign -f -s "$CERT_NAME" --deep "$BUILT_APP" 2>&1

# --- Step 4: Deploy ---
echo "🛑 Stopping running instance..."
pkill -f "$APP_NAME" 2>/dev/null || true
sleep 1

echo "📦 Deploying to /Applications..."
rm -rf "$APP_PATH"
cp -R "$BUILT_APP" /Applications/

# --- Step 5: Register with Launch Services ---
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f -R -trusted "$APP_PATH" 2>/dev/null || true

# --- Step 6: Launch ---
echo "🚀 Launching..."
open "$APP_PATH"

echo ""
echo "✅ Done! If this is the first run with this certificate,"
echo "   authorize in System Settings > Privacy & Security > Accessibility"
echo "   After that, permissions will persist across rebuilds."
