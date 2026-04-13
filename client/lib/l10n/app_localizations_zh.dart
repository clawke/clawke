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
}
