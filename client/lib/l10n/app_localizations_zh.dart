// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get reply => '回复';

  @override
  String get copy => '复制';

  @override
  String get edit => '编辑';

  @override
  String get delete => '删除';

  @override
  String get retry => '重试';

  @override
  String get copied => '已复制';

  @override
  String get deleteMessage => '删除消息';

  @override
  String get deleteMessageConfirm => '确定要删除这条消息吗？';

  @override
  String get cancel => '取消';

  @override
  String get conversations => '会话';

  @override
  String get noConversations => '暂无会话';

  @override
  String loadFailed(String error) {
    return '加载失败: $error';
  }

  @override
  String get selectConversation => '选择一个会话';

  @override
  String get messageDeleted => '此消息已删除';

  @override
  String get edited => '已编辑';

  @override
  String get image => '图片';

  @override
  String get file => '文件';

  @override
  String get newConversation => '新建会话';

  @override
  String get create => '创建';

  @override
  String get settings => '设置';

  @override
  String get themeMode => '主题模式';

  @override
  String get lightMode => '亮色';

  @override
  String get darkMode => '暗色';

  @override
  String get systemMode => '系统';

  @override
  String get developer => '开发者';

  @override
  String get debugLog => '调试日志';

  @override
  String get close => '关闭';

  @override
  String get language => '语言';

  @override
  String get appName => 'Clawke';

  @override
  String get send => '发送';

  @override
  String get typeMessage => '输入消息...';

  @override
  String get upgradePrompt => '新版本可用';

  @override
  String get debugLogTitle => 'DEBUG LOG';

  @override
  String get debugLogSubtitle => '在底部显示 WebSocket 和 CUP 协议日志';

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(int count) {
    return '$count分钟前';
  }

  @override
  String daysAgo(int count) {
    return '$count天前';
  }

  @override
  String get serverDisconnected => '服务器已断开';

  @override
  String get checkServerSetup => '请确认 Clawke Server 已启动并完成授权';

  @override
  String get connecting => '连接中...';

  @override
  String get aiBackendDisconnected => 'OpenClaw Gateway 已断开';

  @override
  String get conversationName => '会话名称';

  @override
  String get conversationNameHint => '输入对方名称或会话标题';

  @override
  String get editMessage => '编辑消息';

  @override
  String replyTo(String content) {
    return '回复: $content';
  }

  @override
  String get sendAttachment => '发送附件';

  @override
  String get notConnected => '未连接';

  @override
  String get navChat => '会话';

  @override
  String get navDashboard => '仪表盘';

  @override
  String get navCron => '定时任务';

  @override
  String get navChannels => '频道管理';

  @override
  String get navSkills => '技能中心';

  @override
  String get loading => '加载中...';

  @override
  String get selectConversationToStart => '选择一个会话开始聊天';

  @override
  String get clearLogs => '清除日志';

  @override
  String get closeLogPanel => '关闭日志面板';

  @override
  String get noLogs => '暂无日志';

  @override
  String get systemDashboard => '系统仪表盘';

  @override
  String get noData => '暂无数据';

  @override
  String get clearConversation => '清空会话';

  @override
  String get clearConversationConfirm => '确定要清空此会话中的所有消息吗？此操作不可撤销。';

  @override
  String get renameConversation => '重命名';

  @override
  String get confirm => '确定';

  @override
  String get deleteConversation => '删除会话';

  @override
  String get deleteConversationConfirm => '确定要删除此会话吗？所有消息将被清除且不可恢复。';

  @override
  String get profile => '我的';

  @override
  String get about => '关于';

  @override
  String get navProfile => '我的';

  @override
  String get serverConnection => 'Clawke 服务器';

  @override
  String get serverAddress => '服务器地址';

  @override
  String get save => '保存';

  @override
  String get saved => '已保存，正在重连...';

  @override
  String get mermaidRender => 'Mermaid 图表渲染';

  @override
  String get mermaidRenderSubtitle => '将 Mermaid 代码块渲染为可视化图表';

  @override
  String get checkUpdate => '检查更新';

  @override
  String get checkingUpdate => '正在检查更新...';

  @override
  String currentVersion(String version) {
    return '当前版本 v$version';
  }

  @override
  String get logout => '登出';

  @override
  String get logoutConfirmTitle => '确认登出';

  @override
  String get logoutConfirmContent => '登出后需要重新登录才能使用 Relay 服务。';

  @override
  String get serverAddressEmpty => '服务器地址不能为空';

  @override
  String get serverAddressInvalidProtocol => '地址必须以 http:// 或 https:// 开头';

  @override
  String get serverAddressInvalidFormat => '地址格式不正确';

  @override
  String get serverUnreachable => '无法连接到服务器，请检查地址和网络';

  @override
  String get appearanceAndLanguage => '外观与语言';

  @override
  String get fontSize => '字体大小';

  @override
  String get fontSizePreview => '预览文字 AaBbCc 你好世界';

  @override
  String get welcomeLogin => '登录 Clawke 账号';

  @override
  String get welcomeManualConfig => '手动配置服务器';

  @override
  String get loginTabLogin => '登录';

  @override
  String get loginTabRegister => '注册';

  @override
  String get loginSubmit => '登录';

  @override
  String get manualConfigTitle => '手动配置服务器';

  @override
  String get manualConfigConnect => '连接';

  @override
  String get general => '通用';

  @override
  String get security => '安全';

  @override
  String get modifyPassword => '修改密码';

  @override
  String get deleteAccount => '注销账户';

  @override
  String get on => '开启';

  @override
  String get off => '关闭';

  @override
  String get termsOfService => '用户协议';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get legal => '法律信息';

  @override
  String get currentPassword => '当前密码';

  @override
  String get newPassword => '新密码';

  @override
  String get confirmNewPassword => '确认新密码';

  @override
  String get enterCurrentPassword => '请输入当前密码';

  @override
  String get enterNewPassword => '请输入新密码';

  @override
  String get pleaseConfirmNewPassword => '请确认新密码';

  @override
  String get passwordMismatch => '两次输入的新密码不一致';

  @override
  String get passwordLengthError => '新密码长度必须为 6-20 位';

  @override
  String get passwordChangedSuccess => '修改密码成功，需要重新登录';

  @override
  String get submitChanges => '提交修改';

  @override
  String get orDivider => '或';

  @override
  String get emailAddress => '邮箱地址';

  @override
  String get enterEmail => '请输入邮箱地址';

  @override
  String get password => '密码';

  @override
  String get enterPassword => '请输入密码';

  @override
  String get forgotPassword => '忘记密码？';

  @override
  String get loginButton => '登录';

  @override
  String get verificationCode => '验证码';

  @override
  String get enterVerificationCode => '请输入邮箱验证码';

  @override
  String get resend => '重新发送';

  @override
  String get getVerificationCode => '获取验证码';

  @override
  String get setPassword => '设置密码';

  @override
  String get setLoginPassword => '请设置一个登录密码';

  @override
  String get registerButton => '注册';

  @override
  String get googleSignIn => 'Google 登录';

  @override
  String get appleSignIn => 'Apple 登录';

  @override
  String get fillEmailAndPassword => '请填写邮箱和密码';

  @override
  String get enterEmailFirst => '请先输入邮箱地址';

  @override
  String sendCodeFailed(String error) {
    return '发送验证码失败: $error';
  }

  @override
  String get fillAllFields => '请填写所有字段';

  @override
  String get googleSignInUnavailable => 'Google 登录暂不可用，请使用邮箱登录';

  @override
  String get appleSignInUnavailable => 'Apple 登录暂不可用，请使用邮箱登录';

  @override
  String loginFailed(String error) {
    return '登录失败: $error';
  }

  @override
  String get forgotPasswordTitle => '忘记密码';

  @override
  String get stepEmail => '邮箱';

  @override
  String get stepVerify => '验证';

  @override
  String get stepReset => '重置';

  @override
  String get enterRegisteredEmail => '请输入你的注册邮箱';

  @override
  String get willSendCodeToReset => '我们将向你的邮箱发送一个验证码来重置密码';

  @override
  String get enterRegisteredEmailHint => '请输入注册时的邮箱';

  @override
  String get sendVerificationCode => '发送验证码';

  @override
  String get enterEmailCode => '输入邮箱验证码';

  @override
  String codeSentTo(String email) {
    return '验证码已发送到 $email';
  }

  @override
  String get enterSixDigitCode => '请输入 6 位验证码';

  @override
  String resendCountdown(int seconds) {
    return '重新发送 (${seconds}s)';
  }

  @override
  String get verifyButton => '验证';

  @override
  String get setNewPasswordTitle => '设置新密码';

  @override
  String get enter6to20Password => '请输入 6-20 位的新密码';

  @override
  String get confirmPasswordLabel => '确认密码';

  @override
  String get reenterNewPassword => '请再次输入新密码';

  @override
  String get resetPasswordButton => '重置密码';

  @override
  String get codeSentCheckEmail => '验证码已发送，请查收邮件';

  @override
  String sendFailed(String error) {
    return '发送失败: $error';
  }

  @override
  String get verifySuccess => '验证成功，请设置新密码';

  @override
  String verifyFailed(String error) {
    return '验证失败: $error';
  }

  @override
  String get codeResent => '验证码已重新发送';

  @override
  String get passwordResetSuccess => '密码重置成功，请用新密码登录';

  @override
  String resetFailed(String error) {
    return '重置失败: $error';
  }

  @override
  String get deleteAccountConfirmContent => '注销后所有数据将丢失，无法恢复，\n是否确认注销？';

  @override
  String get confirmDeleteAccount => '确认注销';

  @override
  String deleteAccountFailed(String error) {
    return '注销失败: $error';
  }

  @override
  String get enterServerAddressToConnect => '输入 Clawke 服务器地址进行连接';

  @override
  String get tokenOptional => 'Token（可选）';

  @override
  String get tokenHint => '留空 = 无认证（仅局域网）';

  @override
  String get connectingStatus => '连接中...';

  @override
  String get enterServerAddressError => '请输入服务器地址';

  @override
  String get connectionTimeout => '连接超时，请检查服务器地址';

  @override
  String get connectionTimeoutShort => '连接超时';

  @override
  String connectionFailed(String error) {
    return '连接失败: $error';
  }

  @override
  String get conversationSettings => '会话设置';

  @override
  String get model => '模型';

  @override
  String get systemPrompt => '系统提示词';

  @override
  String get systemPromptHint => '自定义系统提示词（可选）';

  @override
  String get workDir => '工作目录';

  @override
  String get notSet => '未设置';

  @override
  String get enterConversationName => '输入会话名称';

  @override
  String get generatedAfterCreate => '（创建后生成）';

  @override
  String get defaultModel => '默认模型';

  @override
  String get selectModel => '选择模型';

  @override
  String get refreshModelList => '刷新模型列表';

  @override
  String get gatewayNoModelSupport => '当前 Gateway 不支持指定模型';

  @override
  String get selectSkills => '选择 Skills';

  @override
  String get refreshSkillsList => '刷新 Skills 列表';

  @override
  String get gatewayNoSkillSupport => '当前 Gateway 不支持指定 Skill';

  @override
  String get clickRefreshToRetry => '点击右上角刷新按钮重试';

  @override
  String get priorityTrigger => '优先触发';

  @override
  String get exclusiveTrigger => '必须触发';

  @override
  String get searchSkills => '搜索 Skills...';

  @override
  String get skillsNotEnabled => '未启用';

  @override
  String skillsEnabledCount(int count) {
    return '已启用 $count 个';
  }

  @override
  String get workDirHint => '输入 OpenClaw 工作目录路径';

  @override
  String get workDirNote => '此目录为 OpenClaw 服务器上的路径，非本地路径';

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String monthDay(int month, int day) {
    return '$month月$day日';
  }

  @override
  String get messageInvisible => '[消息不可见]';

  @override
  String yesterdayTime(String time) {
    return '昨天 $time';
  }

  @override
  String get selectAIBackend => '请选择 AI 后端';

  @override
  String get connectionAuthFailed => '连接认证失败';

  @override
  String get relayConnectionRefused => 'Relay 连接被拒绝，Token 可能已过期。\n请重新登录获取新的凭证。';

  @override
  String get later => '稍后';

  @override
  String get reLogin => '重新登录';

  @override
  String get showToken => '显示 Token';

  @override
  String get hideToken => '隐藏 Token';
}
