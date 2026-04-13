import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @reply.
  ///
  /// In zh, this message translates to:
  /// **'回复'**
  String get reply;

  /// No description provided for @copy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get copy;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @copied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get copied;

  /// No description provided for @deleteMessage.
  ///
  /// In zh, this message translates to:
  /// **'删除消息'**
  String get deleteMessage;

  /// No description provided for @deleteMessageConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除这条消息吗？'**
  String get deleteMessageConfirm;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @conversations.
  ///
  /// In zh, this message translates to:
  /// **'会话'**
  String get conversations;

  /// No description provided for @noConversations.
  ///
  /// In zh, this message translates to:
  /// **'暂无会话'**
  String get noConversations;

  /// No description provided for @loadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败: {error}'**
  String loadFailed(String error);

  /// No description provided for @selectConversation.
  ///
  /// In zh, this message translates to:
  /// **'选择一个会话'**
  String get selectConversation;

  /// No description provided for @messageDeleted.
  ///
  /// In zh, this message translates to:
  /// **'此消息已删除'**
  String get messageDeleted;

  /// No description provided for @edited.
  ///
  /// In zh, this message translates to:
  /// **'已编辑'**
  String get edited;

  /// No description provided for @image.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get image;

  /// No description provided for @file.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get file;

  /// No description provided for @newConversation.
  ///
  /// In zh, this message translates to:
  /// **'新建会话'**
  String get newConversation;

  /// No description provided for @create.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get create;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @themeMode.
  ///
  /// In zh, this message translates to:
  /// **'主题模式'**
  String get themeMode;

  /// No description provided for @lightMode.
  ///
  /// In zh, this message translates to:
  /// **'亮色'**
  String get lightMode;

  /// No description provided for @darkMode.
  ///
  /// In zh, this message translates to:
  /// **'暗色'**
  String get darkMode;

  /// No description provided for @systemMode.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get systemMode;

  /// No description provided for @developer.
  ///
  /// In zh, this message translates to:
  /// **'开发者'**
  String get developer;

  /// No description provided for @debugLog.
  ///
  /// In zh, this message translates to:
  /// **'调试日志'**
  String get debugLog;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @appName.
  ///
  /// In zh, this message translates to:
  /// **'Clawke'**
  String get appName;

  /// No description provided for @send.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get send;

  /// No description provided for @typeMessage.
  ///
  /// In zh, this message translates to:
  /// **'输入消息...'**
  String get typeMessage;

  /// No description provided for @upgradePrompt.
  ///
  /// In zh, this message translates to:
  /// **'新版本可用'**
  String get upgradePrompt;

  /// No description provided for @debugLogTitle.
  ///
  /// In zh, this message translates to:
  /// **'DEBUG LOG'**
  String get debugLogTitle;

  /// No description provided for @debugLogSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'在底部显示 WebSocket 和 CUP 协议日志'**
  String get debugLogSubtitle;

  /// No description provided for @justNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count}分钟前'**
  String minutesAgo(int count);

  /// No description provided for @daysAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count}天前'**
  String daysAgo(int count);

  /// No description provided for @serverDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'服务器已断开'**
  String get serverDisconnected;

  /// No description provided for @checkServerSetup.
  ///
  /// In zh, this message translates to:
  /// **'请确认 Clawke Server 已启动并完成授权'**
  String get checkServerSetup;

  /// No description provided for @connecting.
  ///
  /// In zh, this message translates to:
  /// **'连接中...'**
  String get connecting;

  /// No description provided for @aiBackendDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'OpenClaw Gateway 已断开'**
  String get aiBackendDisconnected;

  /// No description provided for @conversationName.
  ///
  /// In zh, this message translates to:
  /// **'会话名称'**
  String get conversationName;

  /// No description provided for @conversationNameHint.
  ///
  /// In zh, this message translates to:
  /// **'输入对方名称或会话标题'**
  String get conversationNameHint;

  /// No description provided for @editMessage.
  ///
  /// In zh, this message translates to:
  /// **'编辑消息'**
  String get editMessage;

  /// No description provided for @replyTo.
  ///
  /// In zh, this message translates to:
  /// **'回复: {content}'**
  String replyTo(String content);

  /// No description provided for @sendAttachment.
  ///
  /// In zh, this message translates to:
  /// **'发送附件'**
  String get sendAttachment;

  /// No description provided for @notConnected.
  ///
  /// In zh, this message translates to:
  /// **'未连接'**
  String get notConnected;

  /// No description provided for @navChat.
  ///
  /// In zh, this message translates to:
  /// **'会话'**
  String get navChat;

  /// No description provided for @navDashboard.
  ///
  /// In zh, this message translates to:
  /// **'仪表盘'**
  String get navDashboard;

  /// No description provided for @navCron.
  ///
  /// In zh, this message translates to:
  /// **'定时任务'**
  String get navCron;

  /// No description provided for @navChannels.
  ///
  /// In zh, this message translates to:
  /// **'频道管理'**
  String get navChannels;

  /// No description provided for @navSkills.
  ///
  /// In zh, this message translates to:
  /// **'技能中心'**
  String get navSkills;

  /// No description provided for @loading.
  ///
  /// In zh, this message translates to:
  /// **'加载中...'**
  String get loading;

  /// No description provided for @selectConversationToStart.
  ///
  /// In zh, this message translates to:
  /// **'选择一个会话开始聊天'**
  String get selectConversationToStart;

  /// No description provided for @clearLogs.
  ///
  /// In zh, this message translates to:
  /// **'清除日志'**
  String get clearLogs;

  /// No description provided for @closeLogPanel.
  ///
  /// In zh, this message translates to:
  /// **'关闭日志面板'**
  String get closeLogPanel;

  /// No description provided for @noLogs.
  ///
  /// In zh, this message translates to:
  /// **'暂无日志'**
  String get noLogs;

  /// No description provided for @systemDashboard.
  ///
  /// In zh, this message translates to:
  /// **'系统仪表盘'**
  String get systemDashboard;

  /// No description provided for @noData.
  ///
  /// In zh, this message translates to:
  /// **'暂无数据'**
  String get noData;

  /// No description provided for @clearConversation.
  ///
  /// In zh, this message translates to:
  /// **'清空会话'**
  String get clearConversation;

  /// No description provided for @clearConversationConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要清空此会话中的所有消息吗？此操作不可撤销。'**
  String get clearConversationConfirm;

  /// No description provided for @renameConversation.
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get renameConversation;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get confirm;

  /// No description provided for @deleteConversation.
  ///
  /// In zh, this message translates to:
  /// **'删除会话'**
  String get deleteConversation;

  /// No description provided for @deleteConversationConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除此会话吗？所有消息将被清除且不可恢复。'**
  String get deleteConversationConfirm;

  /// No description provided for @profile.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get profile;

  /// No description provided for @about.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get about;

  /// No description provided for @navProfile.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get navProfile;

  /// No description provided for @serverConnection.
  ///
  /// In zh, this message translates to:
  /// **'Clawke 服务器'**
  String get serverConnection;

  /// No description provided for @serverAddress.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get serverAddress;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In zh, this message translates to:
  /// **'已保存，正在重连...'**
  String get saved;

  /// No description provided for @mermaidRender.
  ///
  /// In zh, this message translates to:
  /// **'Mermaid 图表渲染'**
  String get mermaidRender;

  /// No description provided for @mermaidRenderSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'将 Mermaid 代码块渲染为可视化图表'**
  String get mermaidRenderSubtitle;

  /// No description provided for @checkUpdate.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get checkUpdate;

  /// No description provided for @checkingUpdate.
  ///
  /// In zh, this message translates to:
  /// **'正在检查更新...'**
  String get checkingUpdate;

  /// No description provided for @currentVersion.
  ///
  /// In zh, this message translates to:
  /// **'当前版本 v{version}'**
  String currentVersion(String version);

  /// No description provided for @logout.
  ///
  /// In zh, this message translates to:
  /// **'登出'**
  String get logout;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认登出'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmContent.
  ///
  /// In zh, this message translates to:
  /// **'登出后需要重新登录才能使用 Relay 服务。'**
  String get logoutConfirmContent;

  /// No description provided for @serverAddressEmpty.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址不能为空'**
  String get serverAddressEmpty;

  /// No description provided for @serverAddressInvalidProtocol.
  ///
  /// In zh, this message translates to:
  /// **'地址必须以 http:// 或 https:// 开头'**
  String get serverAddressInvalidProtocol;

  /// No description provided for @serverAddressInvalidFormat.
  ///
  /// In zh, this message translates to:
  /// **'地址格式不正确'**
  String get serverAddressInvalidFormat;

  /// No description provided for @serverUnreachable.
  ///
  /// In zh, this message translates to:
  /// **'无法连接到服务器，请检查地址和网络'**
  String get serverUnreachable;

  /// No description provided for @appearanceAndLanguage.
  ///
  /// In zh, this message translates to:
  /// **'外观与语言'**
  String get appearanceAndLanguage;

  /// No description provided for @fontSize.
  ///
  /// In zh, this message translates to:
  /// **'字体大小'**
  String get fontSize;

  /// No description provided for @fontSizePreview.
  ///
  /// In zh, this message translates to:
  /// **'预览文字 AaBbCc 你好世界'**
  String get fontSizePreview;

  /// No description provided for @welcomeLogin.
  ///
  /// In zh, this message translates to:
  /// **'登录 Clawke 账号'**
  String get welcomeLogin;

  /// No description provided for @welcomeManualConfig.
  ///
  /// In zh, this message translates to:
  /// **'手动配置服务器'**
  String get welcomeManualConfig;

  /// No description provided for @loginTabLogin.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get loginTabLogin;

  /// No description provided for @loginTabRegister.
  ///
  /// In zh, this message translates to:
  /// **'注册'**
  String get loginTabRegister;

  /// No description provided for @loginSubmit.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get loginSubmit;

  /// No description provided for @manualConfigTitle.
  ///
  /// In zh, this message translates to:
  /// **'手动配置服务器'**
  String get manualConfigTitle;

  /// No description provided for @manualConfigConnect.
  ///
  /// In zh, this message translates to:
  /// **'连接'**
  String get manualConfigConnect;

  /// No description provided for @general.
  ///
  /// In zh, this message translates to:
  /// **'通用'**
  String get general;

  /// No description provided for @security.
  ///
  /// In zh, this message translates to:
  /// **'安全'**
  String get security;

  /// No description provided for @modifyPassword.
  ///
  /// In zh, this message translates to:
  /// **'修改密码'**
  String get modifyPassword;

  /// No description provided for @deleteAccount.
  ///
  /// In zh, this message translates to:
  /// **'注销账户'**
  String get deleteAccount;

  /// No description provided for @on.
  ///
  /// In zh, this message translates to:
  /// **'开启'**
  String get on;

  /// No description provided for @off.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get off;

  /// No description provided for @termsOfService.
  ///
  /// In zh, this message translates to:
  /// **'用户协议'**
  String get termsOfService;

  /// No description provided for @privacyPolicy.
  ///
  /// In zh, this message translates to:
  /// **'隐私政策'**
  String get privacyPolicy;

  /// No description provided for @legal.
  ///
  /// In zh, this message translates to:
  /// **'法律信息'**
  String get legal;

  /// No description provided for @currentPassword.
  ///
  /// In zh, this message translates to:
  /// **'当前密码'**
  String get currentPassword;

  /// No description provided for @newPassword.
  ///
  /// In zh, this message translates to:
  /// **'新密码'**
  String get newPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In zh, this message translates to:
  /// **'确认新密码'**
  String get confirmNewPassword;

  /// No description provided for @enterCurrentPassword.
  ///
  /// In zh, this message translates to:
  /// **'请输入当前密码'**
  String get enterCurrentPassword;

  /// No description provided for @enterNewPassword.
  ///
  /// In zh, this message translates to:
  /// **'请输入新密码'**
  String get enterNewPassword;

  /// No description provided for @pleaseConfirmNewPassword.
  ///
  /// In zh, this message translates to:
  /// **'请确认新密码'**
  String get pleaseConfirmNewPassword;

  /// No description provided for @passwordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的新密码不一致'**
  String get passwordMismatch;

  /// No description provided for @passwordLengthError.
  ///
  /// In zh, this message translates to:
  /// **'新密码长度必须为 6-20 位'**
  String get passwordLengthError;

  /// No description provided for @passwordChangedSuccess.
  ///
  /// In zh, this message translates to:
  /// **'修改密码成功，需要重新登录'**
  String get passwordChangedSuccess;

  /// No description provided for @submitChanges.
  ///
  /// In zh, this message translates to:
  /// **'提交修改'**
  String get submitChanges;

  /// No description provided for @orDivider.
  ///
  /// In zh, this message translates to:
  /// **'或'**
  String get orDivider;

  /// No description provided for @emailAddress.
  ///
  /// In zh, this message translates to:
  /// **'邮箱地址'**
  String get emailAddress;

  /// No description provided for @enterEmail.
  ///
  /// In zh, this message translates to:
  /// **'请输入邮箱地址'**
  String get enterEmail;

  /// No description provided for @password.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get password;

  /// No description provided for @enterPassword.
  ///
  /// In zh, this message translates to:
  /// **'请输入密码'**
  String get enterPassword;

  /// No description provided for @forgotPassword.
  ///
  /// In zh, this message translates to:
  /// **'忘记密码？'**
  String get forgotPassword;

  /// No description provided for @loginButton.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get loginButton;

  /// No description provided for @verificationCode.
  ///
  /// In zh, this message translates to:
  /// **'验证码'**
  String get verificationCode;

  /// No description provided for @enterVerificationCode.
  ///
  /// In zh, this message translates to:
  /// **'请输入邮箱验证码'**
  String get enterVerificationCode;

  /// No description provided for @resend.
  ///
  /// In zh, this message translates to:
  /// **'重新发送'**
  String get resend;

  /// No description provided for @getVerificationCode.
  ///
  /// In zh, this message translates to:
  /// **'获取验证码'**
  String get getVerificationCode;

  /// No description provided for @setPassword.
  ///
  /// In zh, this message translates to:
  /// **'设置密码'**
  String get setPassword;

  /// No description provided for @setLoginPassword.
  ///
  /// In zh, this message translates to:
  /// **'请设置一个登录密码'**
  String get setLoginPassword;

  /// No description provided for @registerButton.
  ///
  /// In zh, this message translates to:
  /// **'注册'**
  String get registerButton;

  /// No description provided for @googleSignIn.
  ///
  /// In zh, this message translates to:
  /// **'Google 登录'**
  String get googleSignIn;

  /// No description provided for @appleSignIn.
  ///
  /// In zh, this message translates to:
  /// **'Apple 登录'**
  String get appleSignIn;

  /// No description provided for @fillEmailAndPassword.
  ///
  /// In zh, this message translates to:
  /// **'请填写邮箱和密码'**
  String get fillEmailAndPassword;

  /// No description provided for @enterEmailFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先输入邮箱地址'**
  String get enterEmailFirst;

  /// No description provided for @sendCodeFailed.
  ///
  /// In zh, this message translates to:
  /// **'发送验证码失败: {error}'**
  String sendCodeFailed(String error);

  /// No description provided for @fillAllFields.
  ///
  /// In zh, this message translates to:
  /// **'请填写所有字段'**
  String get fillAllFields;

  /// No description provided for @googleSignInUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'Google 登录暂不可用，请使用邮箱登录'**
  String get googleSignInUnavailable;

  /// No description provided for @appleSignInUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'Apple 登录暂不可用，请使用邮箱登录'**
  String get appleSignInUnavailable;

  /// No description provided for @loginFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录失败: {error}'**
  String loginFailed(String error);

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In zh, this message translates to:
  /// **'忘记密码'**
  String get forgotPasswordTitle;

  /// No description provided for @stepEmail.
  ///
  /// In zh, this message translates to:
  /// **'邮箱'**
  String get stepEmail;

  /// No description provided for @stepVerify.
  ///
  /// In zh, this message translates to:
  /// **'验证'**
  String get stepVerify;

  /// No description provided for @stepReset.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get stepReset;

  /// No description provided for @enterRegisteredEmail.
  ///
  /// In zh, this message translates to:
  /// **'请输入你的注册邮箱'**
  String get enterRegisteredEmail;

  /// No description provided for @willSendCodeToReset.
  ///
  /// In zh, this message translates to:
  /// **'我们将向你的邮箱发送一个验证码来重置密码'**
  String get willSendCodeToReset;

  /// No description provided for @enterRegisteredEmailHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入注册时的邮箱'**
  String get enterRegisteredEmailHint;

  /// No description provided for @sendVerificationCode.
  ///
  /// In zh, this message translates to:
  /// **'发送验证码'**
  String get sendVerificationCode;

  /// No description provided for @enterEmailCode.
  ///
  /// In zh, this message translates to:
  /// **'输入邮箱验证码'**
  String get enterEmailCode;

  /// No description provided for @codeSentTo.
  ///
  /// In zh, this message translates to:
  /// **'验证码已发送到 {email}'**
  String codeSentTo(String email);

  /// No description provided for @enterSixDigitCode.
  ///
  /// In zh, this message translates to:
  /// **'请输入 6 位验证码'**
  String get enterSixDigitCode;

  /// No description provided for @resendCountdown.
  ///
  /// In zh, this message translates to:
  /// **'重新发送 ({seconds}s)'**
  String resendCountdown(int seconds);

  /// No description provided for @verifyButton.
  ///
  /// In zh, this message translates to:
  /// **'验证'**
  String get verifyButton;

  /// No description provided for @setNewPasswordTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置新密码'**
  String get setNewPasswordTitle;

  /// No description provided for @enter6to20Password.
  ///
  /// In zh, this message translates to:
  /// **'请输入 6-20 位的新密码'**
  String get enter6to20Password;

  /// No description provided for @confirmPasswordLabel.
  ///
  /// In zh, this message translates to:
  /// **'确认密码'**
  String get confirmPasswordLabel;

  /// No description provided for @reenterNewPassword.
  ///
  /// In zh, this message translates to:
  /// **'请再次输入新密码'**
  String get reenterNewPassword;

  /// No description provided for @resetPasswordButton.
  ///
  /// In zh, this message translates to:
  /// **'重置密码'**
  String get resetPasswordButton;

  /// No description provided for @codeSentCheckEmail.
  ///
  /// In zh, this message translates to:
  /// **'验证码已发送，请查收邮件'**
  String get codeSentCheckEmail;

  /// No description provided for @sendFailed.
  ///
  /// In zh, this message translates to:
  /// **'发送失败: {error}'**
  String sendFailed(String error);

  /// No description provided for @verifySuccess.
  ///
  /// In zh, this message translates to:
  /// **'验证成功，请设置新密码'**
  String get verifySuccess;

  /// No description provided for @verifyFailed.
  ///
  /// In zh, this message translates to:
  /// **'验证失败: {error}'**
  String verifyFailed(String error);

  /// No description provided for @codeResent.
  ///
  /// In zh, this message translates to:
  /// **'验证码已重新发送'**
  String get codeResent;

  /// No description provided for @passwordResetSuccess.
  ///
  /// In zh, this message translates to:
  /// **'密码重置成功，请用新密码登录'**
  String get passwordResetSuccess;

  /// No description provided for @resetFailed.
  ///
  /// In zh, this message translates to:
  /// **'重置失败: {error}'**
  String resetFailed(String error);

  /// No description provided for @deleteAccountConfirmContent.
  ///
  /// In zh, this message translates to:
  /// **'注销后所有数据将丢失，无法恢复，\n是否确认注销？'**
  String get deleteAccountConfirmContent;

  /// No description provided for @confirmDeleteAccount.
  ///
  /// In zh, this message translates to:
  /// **'确认注销'**
  String get confirmDeleteAccount;

  /// No description provided for @deleteAccountFailed.
  ///
  /// In zh, this message translates to:
  /// **'注销失败: {error}'**
  String deleteAccountFailed(String error);

  /// No description provided for @enterServerAddressToConnect.
  ///
  /// In zh, this message translates to:
  /// **'输入 Clawke 服务器地址进行连接'**
  String get enterServerAddressToConnect;

  /// No description provided for @tokenOptional.
  ///
  /// In zh, this message translates to:
  /// **'Token（可选）'**
  String get tokenOptional;

  /// No description provided for @tokenHint.
  ///
  /// In zh, this message translates to:
  /// **'留空 = 无认证（仅局域网）'**
  String get tokenHint;

  /// No description provided for @connectingStatus.
  ///
  /// In zh, this message translates to:
  /// **'连接中...'**
  String get connectingStatus;

  /// No description provided for @enterServerAddressError.
  ///
  /// In zh, this message translates to:
  /// **'请输入服务器地址'**
  String get enterServerAddressError;

  /// No description provided for @connectionTimeout.
  ///
  /// In zh, this message translates to:
  /// **'连接超时，请检查服务器地址'**
  String get connectionTimeout;

  /// No description provided for @connectionTimeoutShort.
  ///
  /// In zh, this message translates to:
  /// **'连接超时'**
  String get connectionTimeoutShort;

  /// No description provided for @connectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败: {error}'**
  String connectionFailed(String error);

  /// No description provided for @conversationSettings.
  ///
  /// In zh, this message translates to:
  /// **'会话设置'**
  String get conversationSettings;

  /// No description provided for @model.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get model;

  /// No description provided for @systemPrompt.
  ///
  /// In zh, this message translates to:
  /// **'系统提示词'**
  String get systemPrompt;

  /// No description provided for @systemPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'自定义系统提示词（可选）'**
  String get systemPromptHint;

  /// No description provided for @workDir.
  ///
  /// In zh, this message translates to:
  /// **'工作目录'**
  String get workDir;

  /// No description provided for @notSet.
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get notSet;

  /// No description provided for @enterConversationName.
  ///
  /// In zh, this message translates to:
  /// **'输入会话名称'**
  String get enterConversationName;

  /// No description provided for @generatedAfterCreate.
  ///
  /// In zh, this message translates to:
  /// **'（创建后生成）'**
  String get generatedAfterCreate;

  /// No description provided for @defaultModel.
  ///
  /// In zh, this message translates to:
  /// **'默认模型'**
  String get defaultModel;

  /// No description provided for @selectModel.
  ///
  /// In zh, this message translates to:
  /// **'选择模型'**
  String get selectModel;

  /// No description provided for @refreshModelList.
  ///
  /// In zh, this message translates to:
  /// **'刷新模型列表'**
  String get refreshModelList;

  /// No description provided for @gatewayNoModelSupport.
  ///
  /// In zh, this message translates to:
  /// **'当前 Gateway 不支持指定模型'**
  String get gatewayNoModelSupport;

  /// No description provided for @selectSkills.
  ///
  /// In zh, this message translates to:
  /// **'选择 Skills'**
  String get selectSkills;

  /// No description provided for @refreshSkillsList.
  ///
  /// In zh, this message translates to:
  /// **'刷新 Skills 列表'**
  String get refreshSkillsList;

  /// No description provided for @gatewayNoSkillSupport.
  ///
  /// In zh, this message translates to:
  /// **'当前 Gateway 不支持指定 Skill'**
  String get gatewayNoSkillSupport;

  /// No description provided for @clickRefreshToRetry.
  ///
  /// In zh, this message translates to:
  /// **'点击右上角刷新按钮重试'**
  String get clickRefreshToRetry;

  /// No description provided for @priorityTrigger.
  ///
  /// In zh, this message translates to:
  /// **'优先触发'**
  String get priorityTrigger;

  /// No description provided for @exclusiveTrigger.
  ///
  /// In zh, this message translates to:
  /// **'必须触发'**
  String get exclusiveTrigger;

  /// No description provided for @searchSkills.
  ///
  /// In zh, this message translates to:
  /// **'搜索 Skills...'**
  String get searchSkills;

  /// No description provided for @skillsNotEnabled.
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get skillsNotEnabled;

  /// No description provided for @skillsEnabledCount.
  ///
  /// In zh, this message translates to:
  /// **'已启用 {count} 个'**
  String skillsEnabledCount(int count);

  /// No description provided for @workDirHint.
  ///
  /// In zh, this message translates to:
  /// **'输入 OpenClaw 工作目录路径'**
  String get workDirHint;

  /// No description provided for @workDirNote.
  ///
  /// In zh, this message translates to:
  /// **'此目录为 OpenClaw 服务器上的路径，非本地路径'**
  String get workDirNote;

  /// No description provided for @today.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天'**
  String get yesterday;

  /// No description provided for @monthDay.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日'**
  String monthDay(int month, int day);

  /// No description provided for @messageInvisible.
  ///
  /// In zh, this message translates to:
  /// **'[消息不可见]'**
  String get messageInvisible;

  /// No description provided for @yesterdayTime.
  ///
  /// In zh, this message translates to:
  /// **'昨天 {time}'**
  String yesterdayTime(String time);

  /// No description provided for @selectAIBackend.
  ///
  /// In zh, this message translates to:
  /// **'请选择 AI 后端'**
  String get selectAIBackend;

  /// No description provided for @connectionAuthFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接认证失败'**
  String get connectionAuthFailed;

  /// No description provided for @relayConnectionRefused.
  ///
  /// In zh, this message translates to:
  /// **'Relay 连接被拒绝，Token 可能已过期。\n请重新登录获取新的凭证。'**
  String get relayConnectionRefused;

  /// No description provided for @later.
  ///
  /// In zh, this message translates to:
  /// **'稍后'**
  String get later;

  /// No description provided for @reLogin.
  ///
  /// In zh, this message translates to:
  /// **'重新登录'**
  String get reLogin;

  /// No description provided for @showToken.
  ///
  /// In zh, this message translates to:
  /// **'显示 Token'**
  String get showToken;

  /// No description provided for @hideToken.
  ///
  /// In zh, this message translates to:
  /// **'隐藏 Token'**
  String get hideToken;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
