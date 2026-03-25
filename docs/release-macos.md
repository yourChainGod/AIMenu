# macOS Release Workflow

## Prerequisites
- Xcode command line tools
- `create-dmg`
- 可选：Apple Developer `Developer ID Application` 证书
- 可选：`notarytool` keychain profile

## Build Release App
```bash
xcodebuild -project AIMenu.xcodeproj \
  -scheme AIMenu \
  -configuration Release \
  -derivedDataPath .build/DerivedData \
  -destination 'platform=macOS' build
```

产物路径：

- `.build/DerivedData/Build/Products/Release/AIMenu.app`

## Build DMG

```bash
mkdir -p /tmp/AIMenu-dmg-stage
cp -R .build/DerivedData/Build/Products/Release/AIMenu.app /tmp/AIMenu-dmg-stage/

create-dmg \
  --volname 'AIMenu 1.0.6' \
  --window-size 640 380 \
  --icon-size 128 \
  --icon 'AIMenu.app' 160 190 \
  --app-drop-link 480 190 \
  'artifacts/AIMenu-1.0.6.dmg' \
  '/tmp/AIMenu-dmg-stage/'
```

## Optional Signing / Notarization

仓库当前可以完成 `.app` 与 `.dmg` 打包。

若要做正式分发，还需要：

- 用 `Developer ID Application` 对 `.app` 签名
- 提交 notarization
- 对外发布 notarized 的 DMG

## Notes
- 不要把整个 `Release` 目录直接打进 DMG，只拷贝 `AIMenu.app`
- 否则会把 `dSYM`、`swiftmodule` 等调试产物一起带进去
