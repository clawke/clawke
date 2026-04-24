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
  String get skillsPageSubtitle =>
      'Scan SKILL.md files in skills/ directories. Create, edit, disable, and delete managed skills.';

  @override
  String get skillsMetricAll => 'All';

  @override
  String get skillsMetricEnabled => 'Enabled';

  @override
  String get skillsRefresh => 'Refresh';

  @override
  String get skillsNewSkill => 'New Skill';

  @override
  String get skillsStatusAll => 'All';

  @override
  String get skillsStatusEnabled => 'Enabled';

  @override
  String get skillsStatusDisabled => 'Disabled';

  @override
  String get skillsSourceAll => 'All Sources';

  @override
  String get skillsSourceManaged => 'Managed';

  @override
  String get skillsSourceExternal => 'External';

  @override
  String get skillsSourceReadonly => 'Read-only';

  @override
  String get skillsConflict => 'Conflict';

  @override
  String skillsTriggerLabel(String trigger) {
    return 'Trigger: $trigger';
  }

  @override
  String get skillsCreated => 'Skill created';

  @override
  String get skillsSaved => 'Skill saved';

  @override
  String get skillsDeleted => 'Skill deleted';

  @override
  String get skillsDeleteTitle => 'Delete skill?';

  @override
  String skillsDeleteMessage(String name) {
    return 'This will delete $name\'s SKILL.md and skill directory. This action cannot be undone.';
  }

  @override
  String get skillsEditTitle => 'Edit Skill';

  @override
  String get skillsFieldName => 'Name';

  @override
  String get skillsFieldCategory => 'Category';

  @override
  String get skillsFieldTrigger => 'Trigger';

  @override
  String get skillsFieldDescription => 'Description';

  @override
  String get skillsDescriptionRequired => 'Enter a description';

  @override
  String get skillsSkillMdBody => 'SKILL.md Body';

  @override
  String get skillsFieldRequired => 'Required';

  @override
  String get skillsPathPartInvalid =>
      'Use letters, numbers, dots, underscores, and hyphens only';

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
  String get switchAccount => 'Switch Account';

  @override
  String get addAccount => 'Add Account';

  @override
  String get currentAccount => 'Current';

  @override
  String get accountExpired => 'Session expired, please log in again';

  @override
  String get switchAccountHint => 'Tap an account to switch';

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

  @override
  String get orDivider => 'or';

  @override
  String get emailAddress => 'Email';

  @override
  String get enterEmail => 'Enter email address';

  @override
  String get password => 'Password';

  @override
  String get enterPassword => 'Enter password';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get loginButton => 'Log In';

  @override
  String get verificationCode => 'Verification Code';

  @override
  String get enterVerificationCode => 'Enter verification code';

  @override
  String get resend => 'Resend';

  @override
  String get getVerificationCode => 'Get Code';

  @override
  String get setPassword => 'Set Password';

  @override
  String get setLoginPassword => 'Set a login password';

  @override
  String get registerButton => 'Register';

  @override
  String get googleSignIn => 'Sign in with Google';

  @override
  String get appleSignIn => 'Sign in with Apple';

  @override
  String get fillEmailAndPassword => 'Please fill in email and password';

  @override
  String get enterEmailFirst => 'Please enter email first';

  @override
  String sendCodeFailed(String error) {
    return 'Failed to send code: $error';
  }

  @override
  String get fillAllFields => 'Please fill all fields';

  @override
  String get googleSignInUnavailable =>
      'Google sign-in unavailable, please use email';

  @override
  String get appleSignInUnavailable =>
      'Apple sign-in unavailable, please use email';

  @override
  String loginFailed(String error) {
    return 'Login failed: $error';
  }

  @override
  String get forgotPasswordTitle => 'Forgot Password';

  @override
  String get stepEmail => 'Email';

  @override
  String get stepVerify => 'Verify';

  @override
  String get stepReset => 'Reset';

  @override
  String get enterRegisteredEmail => 'Enter your registered email';

  @override
  String get willSendCodeToReset =>
      'We\'ll send a verification code to reset your password';

  @override
  String get enterRegisteredEmailHint => 'Enter registration email';

  @override
  String get sendVerificationCode => 'Send Code';

  @override
  String get enterEmailCode => 'Enter email verification code';

  @override
  String codeSentTo(String email) {
    return 'Code sent to $email';
  }

  @override
  String get enterSixDigitCode => 'Enter 6-digit code';

  @override
  String resendCountdown(int seconds) {
    return 'Resend (${seconds}s)';
  }

  @override
  String get verifyButton => 'Verify';

  @override
  String get setNewPasswordTitle => 'Set New Password';

  @override
  String get enter6to20Password => 'Enter 6-20 character password';

  @override
  String get confirmPasswordLabel => 'Confirm Password';

  @override
  String get reenterNewPassword => 'Re-enter new password';

  @override
  String get resetPasswordButton => 'Reset Password';

  @override
  String get codeSentCheckEmail => 'Code sent, check your email';

  @override
  String sendFailed(String error) {
    return 'Send failed: $error';
  }

  @override
  String get verifySuccess => 'Verified, please set new password';

  @override
  String verifyFailed(String error) {
    return 'Verification failed: $error';
  }

  @override
  String get codeResent => 'Code resent';

  @override
  String get passwordResetSuccess =>
      'Password reset, please log in with new password';

  @override
  String resetFailed(String error) {
    return 'Reset failed: $error';
  }

  @override
  String get deleteAccountConfirmContent =>
      'All data will be permanently deleted after account deletion.\nAre you sure?';

  @override
  String get confirmDeleteAccount => 'Confirm Delete';

  @override
  String deleteAccountFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get enterServerAddressToConnect =>
      'Enter Clawke server address to connect';

  @override
  String get tokenOptional => 'Token (optional)';

  @override
  String get tokenHint => 'Leave empty for no auth (LAN only)';

  @override
  String get connectingStatus => 'Connecting...';

  @override
  String get enterServerAddressError => 'Please enter server address';

  @override
  String get connectionTimeout =>
      'Connection timeout, please check server address';

  @override
  String get connectionTimeoutShort => 'Connection timeout';

  @override
  String connectionFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get conversationSettings => 'Conversation Settings';

  @override
  String get model => 'Model';

  @override
  String get systemPrompt => 'System Prompt';

  @override
  String get systemPromptHint => 'Custom system prompt (optional)';

  @override
  String get workDir => 'Work Directory';

  @override
  String get notSet => 'Not set';

  @override
  String get enterConversationName => 'Enter conversation name';

  @override
  String get generatedAfterCreate => '(generated after creation)';

  @override
  String get defaultModel => 'Default Model';

  @override
  String get selectModel => 'Select Model';

  @override
  String get refreshModelList => 'Refresh model list';

  @override
  String get gatewayNoModelSupport =>
      'Current gateway does not support model selection';

  @override
  String get selectSkills => 'Select Skills';

  @override
  String get refreshSkillsList => 'Refresh skills list';

  @override
  String get gatewayNoSkillSupport =>
      'Current gateway does not support skill selection';

  @override
  String get clickRefreshToRetry => 'Click refresh button to retry';

  @override
  String get priorityTrigger => 'Priority';

  @override
  String get exclusiveTrigger => 'Exclusive';

  @override
  String get searchSkills => 'Search Skills...';

  @override
  String get skillsNotEnabled => 'None enabled';

  @override
  String skillsEnabledCount(int count) {
    return '$count enabled';
  }

  @override
  String get workDirHint => 'Enter OpenClaw work directory path';

  @override
  String get workDirNote => 'This is a path on the OpenClaw server, not local';

  @override
  String get noModelsAvailable =>
      'No models available. Check Gateway connection.';

  @override
  String get noSkillsAvailable => 'No skills installed.';

  @override
  String get skillModePriority => 'Prefer these skills';

  @override
  String get skillModeExclusive => 'Must use these skills';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String monthDay(int month, int day) {
    return '$month/$day';
  }

  @override
  String get messageInvisible => '[Message not visible]';

  @override
  String yesterdayTime(String time) {
    return 'Yesterday $time';
  }

  @override
  String get selectAIBackend => 'Please select AI backend';

  @override
  String get connectionAuthFailed => 'Connection Auth Failed';

  @override
  String get relayConnectionRefused =>
      'Relay connection refused, token may have expired.\nPlease log in again to get new credentials.';

  @override
  String get later => 'Later';

  @override
  String get reLogin => 'Log In Again';

  @override
  String get showToken => 'Show Token';

  @override
  String get hideToken => 'Hide Token';

  @override
  String get aiThinking => 'Thinking...';

  @override
  String get cardGeneratingOptions => 'Generating options...';

  @override
  String get cardGeneratingApproval => 'Generating approval request...';

  @override
  String get cardNeedConfirm => 'Confirmation Required';

  @override
  String get cardApprove => 'Allow';

  @override
  String get cardDeny => 'Deny';

  @override
  String get cardApproved => 'Allowed';

  @override
  String get cardDenied => 'Denied';

  @override
  String cardSelected(String choice) {
    return 'Selected: $choice';
  }

  @override
  String cardApprovedPersist(String command) {
    return '✅ Allowed: $command';
  }

  @override
  String cardDeniedPersist(String command) {
    return '🚫 Denied: $command';
  }

  @override
  String cardSelectedPersist(String choice) {
    return '✅ Selected: $choice';
  }

  @override
  String get cardRiskHigh => 'High Risk';

  @override
  String get cardRiskMedium => 'Medium Risk';

  @override
  String get cardRiskLow => 'Low Risk';

  @override
  String get cardOtherOptionHint =>
      'You can also type your answer in the input box below';

  @override
  String get cardCopyCode => 'Copy Code';

  @override
  String get cardCodeCopied => 'Copied';

  @override
  String get errorAuthFailed =>
      'AI service authentication failed. Please check your API key.';

  @override
  String get errorNetworkError =>
      'AI service connection timeout. Please check your network.';

  @override
  String get errorRateLimited => 'Too many requests. Please try again later.';

  @override
  String get errorModelUnavailable =>
      'Selected AI model is unavailable. Please check model configuration.';

  @override
  String get errorNoReply =>
      'AI did not generate a reply. Please try again or start a new conversation.';

  @override
  String errorAgentError(String detail) {
    return 'AI processing error: $detail';
  }
}
