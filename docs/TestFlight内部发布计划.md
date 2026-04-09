# TestFlight 内部发布计划（Spatial Data Recorder）

## 1. 目标与适用范围

本文用于指导公司内部人员通过 TestFlight 安装和使用 iOS 版 Spatial Data Recorder，并给出完整的发布流程、环境变量策略、安全注意事项和版本迭代计划。

适用场景：

- 仅公司内部使用，不对外公开上架
- 需要持续迭代，支持小范围灰度
- 使用 Flutter 开发，iOS 包通过 Xcode / CI 构建

---

## 2. 关键结论（先看这个）

### 2.1 本地 .env 在构建后会不会保留

会保留。

当前项目使用 flutter_dotenv 在启动时读取 .env，并且在 pubspec 中将 .env 声明为 Flutter 资源。构建 IPA 时，.env 会被打包进应用资源。

结论：

- 构建时机器上的 .env 内容，会进入该次构建产物
- 构建完成后再修改本地 .env，不会影响已经上传的 TestFlight 构建
- .gitignore 只影响是否提交仓库，不影响打包

### 2.2 安全含义

- UPLOAD_AUTH_TOKEN 属于可被提取的信息，不应视为安全密钥
- 生产环境建议使用短期令牌或登录换票，不要使用长期固定 Token
- 上传地址建议使用 HTTPS，避免明文传输风险

---

## 3. 分发方式选择

### 3.1 推荐方案

优先使用 TestFlight 进行内部发布。

原因：

- 安装路径统一，用户侧操作简单
- 不需要收集设备 UDID
- 支持多版本迭代和快速回归

### 3.2 TestFlight 的边界

- 单个构建有效期 90 天
- 需要 Apple Developer Program（99 美元/年）
- 内部测试成员需要在 App Store Connect 团队内

---

## 4. 角色与职责

建议最少配置以下角色：

1. 发布负责人（1 人）

- 管理证书、签名、上传、发布节奏

2. 后端负责人（1 人）

- 管理上传接口、Token 策略、服务稳定性

3. 业务验收人（2-5 人）

- 真机验证录制、停止、上传、补传等核心流程

---

## 5. 一次性准备清单（首次上线前）

1. Apple 账号与权限

- 开通组织型 Apple Developer Program
- App Store Connect 中授予发布负责人 App Manager 或 Admin

2. 应用标识

- 创建唯一 Bundle ID（与 Runner 保持一致）
- 在 App Store Connect 新建 App 记录

3. 签名能力

- Xcode 中 Runner Target 开启 Automatically manage signing
- Debug/Release 均绑定正确 Team

4. iOS 权限文案

- 确认相机、运动权限文案与实际行为一致
- 若未来录音，补充麦克风权限文案

5. 网络与域名

- 上传服务优先切 HTTPS
- 证书有效期、域名可用性、跨网段可达性提前验证

---

## 6. 环境变量治理方案（必须执行）

## 6.1 文件分层建议

在项目根目录维护：

- .env.dev
- .env.testflight
- .env.prod
- .env-example

发布时仅将目标环境文件复制为 .env 后再构建。

## 6.2 发布前环境切换流程（手工版）

1. 备份当前 .env
2. 用 .env.testflight 覆盖 .env
3. 执行构建
4. 上传完成后恢复开发 .env

## 6.3 推荐命令（Windows PowerShell）

示例：
Copy-Item .env.testflight .env -Force
flutter clean
flutter pub get
flutter build ipa --release --build-name 1.0.1 --build-number 101

构建后可恢复：
Copy-Item .env.dev .env -Force

## 6.4 强制校验（建议）

发布前增加人工核对项：

- UPLOAD_BASE_URL 是否为测试/预发地址
- UPLOAD_AUTH_TOKEN 是否为测试令牌（可轮换）
- 是否启用 HTTPS

---

## 7. TestFlight 发布 SOP（每次发版）

1. 合并代码并打发布标签

- 确保主分支处于可发布状态

2. 切换环境变量

- 将 .env.testflight 复制到 .env

3. 版本号规划

- build-name 使用语义版本（如 1.0.1）
- build-number 每次递增（如 101, 102, 103）

4. 本地构建

- flutter clean
- flutter pub get
- flutter build ipa --release --build-name 1.0.1 --build-number 101

5. 上传构建

- 方式 A：Xcode Organizer 上传 Archive
- 方式 B：Transporter 上传 IPA

6. 等待 Processing

- App Store Connect 中等待构建处理完成
- 若 15-30 分钟未出现，检查签名、版本号、上传日志

7. 配置 TestFlight 元信息

- 填写本次变更说明、测试重点、已知限制

8. 分配内部测试组

- 添加测试人员（公司 Apple ID）
- 发送测试说明和回归重点

9. 发布后验证

- 至少 2 台不同型号 iPhone 安装验证
- 验证核心路径：录制、停止、自动上传、失败重试、手动补传

10. 发布记录

- 在 docs/ 或内部 Wiki 记录版本、构建号、环境、回滚点

---

## 8. 发布验收清单（建议逐项勾选）

### 8.1 功能验收

- 应用可安装并首次启动成功
- 权限弹窗正常，拒绝权限时提示可理解
- 能正常开始/停止录制
- 录制后自动入队上传
- 上传失败可重试，成功后状态更新正确

### 8.2 数据验收

- 会话目录结构完整
- ZIP 包包含必需文件（data.mov、data.jsonl、calibration.json、metadata.json）
- 后端能正确解析并入库

### 8.3 性能与稳定性

- 连续录制 5-10 段无明显内存异常
- 弱网/断网恢复后上传可继续
- 设备锁屏、前后台切换后状态一致

### 8.4 安全与合规

- 不使用长期生产密钥
- 上传链路使用 HTTPS
- 隐私说明与采集行为一致
- 内部数据保留/删除策略明确

---

## 9. 常见问题与处理

1. TestFlight 看不到新构建

- 检查 build-number 是否递增
- 检查上传账号是否与目标 App 一致
- 等待 Processing 完成后刷新

2. 安装失败或闪退

- 检查签名 Team、Bundle ID
- 检查最低 iOS 版本与设备兼容性

3. 上传总失败

- 先验证服务健康检查与磁盘空间
- 检查上传根目录是否为绝对路径
- 检查 Token 是否与后端 AUTH_TOKENS 一致

4. 内网可用、外网不可用

- 检查 DNS、网关策略、防火墙白名单
- 建议统一走可公网访问且受控的 HTTPS 网关

---

## 10. 7 天落地计划（可直接执行）

第 1 天：账号与签名打通

- 完成 Apple 权限、Bundle ID、App Store Connect App 创建

第 2 天：环境治理

- 建立 .env.dev / .env.testflight / .env.prod
- 确认测试环境 HTTPS 地址

第 3 天：首包发布

- 完成首个 TestFlight 构建上传

第 4 天：小范围试点

- 邀请 3-5 位内部同事，收集问题

第 5 天：修复与二次发布

- 修复关键问题，build-number +1 重新发布

第 6 天：扩大覆盖

- 扩到目标部门，建立反馈群与缺陷分级

第 7 天：制度化

- 固化发布检查表、回滚机制、90 天到期提醒

---

## 11. 最低安全基线（内部应用也必须满足）

1. 禁止将长期有效生产 Token 固定在 .env 并随包下发
2. 必须支持 Token 轮换与失效
3. 上传链路必须 HTTPS
4. 必须有版本回滚路径
5. 必须有日志与问题追踪机制

---

## 12. 附录：本项目发布前建议立即处理项

1. 将 UPLOAD_BASE_URL 从 HTTP 切换为 HTTPS
2. 为 TestFlight 准备专用 Token（短期、可撤销）
3. 为发布流程增加“环境变量核对截图”步骤
4. 在每次发版记录中写明：build-name、build-number、.env 来源、回滚版本

---

文档版本：v1.0
更新日期：2026-04-09
