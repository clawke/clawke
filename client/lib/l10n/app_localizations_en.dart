// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get reply => 'Reply';

  @override
  String get copy => 'Copy';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get retry => 'Retry';

  @override
  String get copied => 'Copied';

  @override
  String get deleteMessage => 'Delete Message';

  @override
  String get deleteMessageConfirm =>
      'Are you sure you want to delete this message?';

  @override
  String get cancel => 'Cancel';

  @override
  String get conversations => 'Conversations';

  @override
  String get noConversations => 'No conversations';

  @override
  String loadFailed(String error) {
    return 'Load failed: $error';
  }

  @override
  String get selectConversation => 'Select a conversation';

  @override
  String get messageDeleted => 'This message has been deleted';

  @override
  String get edited => 'edited';

  @override
  String get image => 'Image';

  @override
  String get file => 'File';

  @override
  String get newConversation => 'New Conversation';

  @override
  String get create => 'Create';

  @override
  String get settings => 'Settings';

  @override
  String get themeMode => 'Theme';

  @override
  String get lightMode => 'Light';

  @override
  String get darkMode => 'Dark';

  @override
  String get systemMode => 'System';

  @override
  String get developer => 'Developer';

  @override
  String get debugLog => 'Debug Log';

  @override
  String get close => 'Close';

  @override
  String get language => 'Language';

  @override
  String get appName => 'Clawke';

  @override
  String get send => 'Send';

  @override
  String get typeMessage => 'Type a message...';

  @override
  String get upgradePrompt => 'New version available';

  @override
  String get debugLogTitle => 'DEBUG LOG';

  @override
  String get debugLogSubtitle =>
      'Show WebSocket and CUP protocol logs at bottom';

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String daysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String get serverDisconnected => 'Server disconnected';

  @override
  String get checkServerSetup =>
      'Please ensure your Clawke Server is running and authorized';

  @override
  String get connecting => 'Connecting...';

  @override
  String get aiBackendDisconnected => 'OpenClaw Gateway disconnected';

  @override
  String get conversationName => 'Conversation name';

  @override
  String get conversationNameHint => 'Enter a name or title';

  @override
  String get editMessage => 'Edit message';

  @override
  String replyTo(String content) {
    return 'Reply: $content';
  }

  @override
  String get sendAttachment => 'Send attachment';

  @override
  String get notConnected => 'Not connected';

  @override
  String get navChat => 'Chat';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navCron => 'Scheduled Tasks';

  @override
  String get navChannels => 'Channels';

  @override
  String get navSkills => 'Skills';

  @override
  String get loading => 'Loading...';

  @override
  String get selectConversationToStart =>
      'Select a conversation to start chatting';

  @override
  String get clearLogs => 'Clear logs';

  @override
  String get closeLogPanel => 'Close log panel';

  @override
  String get noLogs => 'No logs';

  @override
  String get systemDashboard => 'System Dashboard';

  @override
  String get noData => 'No data available';

  @override
  String get clearConversation => 'Clear Conversation';

  @override
  String get clearConversationConfirm =>
      'Are you sure you want to clear all messages in this conversation? This action cannot be undone.';

  @override
  String get renameConversation => 'Rename';

  @override
  String get confirm => 'Confirm';

  @override
  String get deleteConversation => 'Delete Conversation';

  @override
  String get deleteConversationConfirm =>
      'Are you sure you want to delete this conversation? All messages will be permanently removed.';

  @override
  String get profile => 'Profile';

  @override
  String get about => 'About';

  @override
  String get navProfile => 'Me';

  @override
  String get serverConnection => 'Clawke Server';

  @override
  String get serverAddress => 'Server Address';

  @override
  String get save => 'Save';

  @override
  String get saved => 'Saved, reconnecting...';

  @override
  String get mermaidRender => 'Mermaid Chart Rendering';

  @override
  String get mermaidRenderSubtitle =>
      'Render Mermaid code blocks as visual charts';

  @override
  String get checkUpdate => 'Check for Updates';

  @override
  String get checkingUpdate => 'Checking for updates...';

  @override
  String currentVersion(String version) {
    return 'Current version v$version';
  }

  @override
  String get logout => 'Log Out';

  @override
  String get logoutConfirmTitle => 'Confirm Log Out';

  @override
  String get logoutConfirmContent =>
      'You will need to log in again to use Relay services.';

  @override
  String get serverAddressEmpty => 'Server address cannot be empty';

  @override
  String get serverAddressInvalidProtocol =>
      'Address must start with http:// or https://';

  @override
  String get serverAddressInvalidFormat => 'Invalid address format';

  @override
  String get serverUnreachable =>
      'Cannot connect to server, please check the address and network';

  @override
  String get appearanceAndLanguage => 'Appearance & Language';

  @override
  String get fontSize => 'Font Size';

  @override
  String get fontSizePreview => 'Preview text AaBbCc Hello World';

  @override
  String get welcomeLogin => 'Log In to Clawke';

  @override
  String get welcomeManualConfig => 'Configure Server Manually';

  @override
  String get loginTabLogin => 'Login';

  @override
  String get loginTabRegister => 'Register';

  @override
  String get loginSubmit => 'Login';

  @override
  String get manualConfigTitle => 'Configure Server Manually';

  @override
  String get manualConfigConnect => 'Connect';

  @override
  String get general => 'General';

  @override
  String get security => 'Security';

  @override
  String get modifyPassword => 'Change Password';

  @override
  String get deleteAccount => 'Delete Account';

  @override
  String get on => 'On';

  @override
  String get off => 'Off';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get legal => 'Legal';

  @override
  String get currentPassword => 'Current Password';

  @override
  String get newPassword => 'New Password';

  @override
  String get confirmNewPassword => 'Confirm New Password';

  @override
  String get enterCurrentPassword => 'Please enter current password';

  @override
  String get enterNewPassword => 'Please enter new password';

  @override
  String get pleaseConfirmNewPassword => 'Please confirm new password';

  @override
  String get passwordMismatch => 'New passwords do not match';

  @override
  String get passwordLengthError => 'Password must be 6-20 characters';

  @override
  String get passwordChangedSuccess => 'Password changed, please log in again';

  @override
  String get submitChanges => 'Submit';
}
