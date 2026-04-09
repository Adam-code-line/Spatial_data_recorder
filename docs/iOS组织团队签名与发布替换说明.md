# iOS 组织团队签名与发布替换说明（Spatial Data Recorder）

更新日期：2026-04-09

## 1. 结论

是的，需要在 Xcode 里把签名团队切换到你公司的团队（Jingzhan Technology (Beijing) Co., Ltd）。

当前项目已经把主应用 Bundle ID 改成了 `com.momax.cap`，发布方向是正确的。要保证能正常构建和发布，关键是把签名团队切到公司团队，并保持 Bundle ID 与 App Store Connect 一致。

## 2. 当前项目扫描结果（已确认）

1. 主应用 Bundle ID（Runner）已是 `com.momax.cap`。
2. 测试 Target Bundle ID（RunnerTests）已是 `com.momax.cap.RunnerTests`。
3. `DEVELOPMENT_TEAM` 仍是旧 Team ID：`28XXZQ95P6`（需要替换为你公司团队对应的 Team ID`9AZ652M3G3`）。
4. 项目使用 Automatic Signing（`CODE_SIGN_STYLE = Automatic`），可继续沿用。

## 3. Runner 中需要替换的内容

## 3.1 必须替换（影响构建与发布）

1. 签名团队 Team（必须）

- Xcode 路径：`Runner` target -> `Signing & Capabilities` -> `Team`
- 目标：选择 `Jingzhan Technology (Beijing) Co., Ltd`
- 原因：发布证书、描述文件、权限签名都与 Team 强绑定。

2. DEVELOPMENT_TEAM（必须）

- 文件：`ios/Runner.xcodeproj/project.pbxproj`
- 当前值：`28XXZQ95P6`
- 要求：改为你公司团队真实 Team ID（10 位字母数字）
- 说明：在 Xcode 中切 Team 后，这个值通常会自动改写，不建议手工盲改。

3. 主应用 Bundle Identifier（必须与 App Store Connect 一致）

- Xcode 路径：`Runner` target -> `General` -> `Identity` -> `Bundle Identifier`
- 当前目标值：`com.momax.cap`
- 要求：与 App Store Connect 里该 App 的 Bundle ID 完全一致。

## 3.2 建议替换（保证本地测试与 CI 一致）

1. RunnerTests 的签名与 Bundle ID

- 建议保持：`com.momax.cap.RunnerTests`
- 说明：不影响 TestFlight 主包上传，但影响测试 Target 的构建稳定性。

2. Provisioning Profile

- 当前是自动签名下空值（`PROVISIONING_PROFILE_SPECIFIER = ""`）
- 建议：先保持自动签名。若公司策略要求手工签名，再按 IT/发布策略指定 Profile。

## 3.3 不要替换（与上架无关，改了可能引入功能回归）

以下字符串看起来像 ID，但不属于上架签名 ID，不建议为了发布去改：

1. Flutter MethodChannel / PlatformView 通道名

- `ios/Runner/AppDelegate.swift`
- `ios/Runner/RecorderFlutterBridge.swift`

2. DispatchQueue label / Queue name

- `ios/Runner/CameraPreviewController.swift`
- `ios/Runner/SlamRecordingSession.swift`

这些字符串用于内部通信或调试命名，不影响 App Store 的签名与上架。

## 4. 推荐操作步骤（可直接执行）

1. 在 Mac 上打开 `ios/Runner.xcworkspace`（不要打开 `.xcodeproj`）。
2. 选中 `Runner` target，进入 `Signing & Capabilities`。
3. Team 选择：`Jingzhan Technology (Beijing) Co., Ltd`。
4. 勾选 `Automatically manage signing`。
5. 在 `General` 页确认 Bundle Identifier 为 `com.momax.cap`。
6. 切到 `RunnerTests` target，确认 Team 与 Bundle ID 也正确（建议）。
7. Product -> Clean Build Folder。
8. 执行 Archive（Any iOS Device）。
9. 在 Organizer 上传到 TestFlight。

## 5. 发布前核对清单

1. App Store Connect 中 App 的 Bundle ID 是 `com.momax.cap`。
2. Xcode 中 Runner 的 Team 是公司团队。
3. Debug/Release/Profile 均使用同一 Team。
4. 构建号（build number）已递增。
5. Archive 阶段无签名错误（尤其是 `No profiles for ...` / `requires a development team`）。

## 6. 常见报错与处理

1. `No profiles for 'com.momax.cap' were found`

- 处理：确认 Team 选对；保持自动签名；登录正确 Apple ID；重新 Archive。

2. `Signing for "Runner" requires a development team`

- 处理：在 Runner target 的 Signing 页明确选择公司 Team。

3. `Bundle identifier mismatch`

- 处理：统一 Xcode 的 Bundle ID 与 App Store Connect App 记录。

## 7. 你当前最需要做的一步

当前项目最关键的缺口是：把 Team 从旧 Team ID（`28XXZQ95P6`）切换到公司团队对应的 Team。

只要 Team 与 Bundle ID（`com.momax.cap`）匹配，通常就可以正常构建并发布到 TestFlight。
