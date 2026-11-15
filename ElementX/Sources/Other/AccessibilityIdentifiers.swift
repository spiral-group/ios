//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum A11yIdentifiers {
    static let alertInfo = AlertInfo()
    static let analyticsPromptScreen = AnalyticsPromptScreen()
    static let appLockScreen = AppLockScreen()
    static let appLockSetupBiometricsScreen = AppLockSetupBiometricsScreen()
    static let appLockSetupPINScreen = AppLockSetupPINScreen()
    static let appLockSetupSettingsScreen = AppLockSetupSettingsScreen()
    static let bugReportScreen = BugReportScreen()
    static let changeServerScreen = ChangeServer()
    static let encryptionResetScreen = EncryptionResetScreen()
    static let encryptionResetPasswordScreen = EncryptionResetPasswordScreen()
    static let homeScreen = HomeScreen()
    static let homeTabs = HomeTabs()
    static let loginScreen = LoginScreen()
    static let authenticationStartScreen = AuthenticationStartScreen()
    static let invitePasteSheet = InvitePasteSheet() // AGENT-PLATFORM (Brief 0073).
    static let invitePeopleScreen = InvitePeopleScreen() // AGENT-PLATFORM (Brief 0073).
    static let reportContent = ReportContent()
    static let joinRoomScreen = JoinRoomScreen()
    static let roomScreen = RoomScreen()
    static let roomDetailsScreen = RoomDetailsScreen()
    static let roomNotificationSettingsScreen = RoomNotificationSettingsScreen()
    static let roomRolesAndPermissionsScreen = RoomRolesAndPermissionsScreen()
    static let secureBackupScreen = SecureBackupScreen()
    static let secureBackupKeyBackupScreen = SecureBackupKeyBackupScreen()
    static let secureBackupRecoveryKeyScreen = SecureBackupRecoveryKeyScreen()
    static let serverConfirmationScreen = ServerConfirmationScreen()
    static let sessionVerificationScreen = SessionVerificationScreen()
    static let settingsScreen = SettingsScreen()
    static let softLogoutScreen = SoftLogoutScreen()
    static let startChatScreen = StartChatScreen()
    static let roomMemberDetailsScreen = RoomMemberDetailsScreen()
    static let createRoomScreen = CreateRoomScreen()
    static let inviteUsersScreen = InviteUsersScreen()
    static let notificationSettingsScreen = NotificationSettingsScreen()
    static let notificationSettingsEditScreen = NotificationSettingsEditScreen()
    static let pollFormScreen = PollFormScreen()
    static let roomPollsHistoryScreen = RoomPollsHistoryScreen()
    static let roomMembersListScreen = RoomMembersListScreen()
    static let manageRoomMemberSheet = ManageRoomMemberSheet()
    static let spacesScreen = SpacesScreen()
    static let spaceScreen = SpaceScreen()
    static let spaceAddRoomsScreen = SpaceAddRoomsScreen()
    static let searchScreen = SearchScreen()
    static let spaceSettingsScreen = SpaceSettingsScreen()
    static let linkNewDeviceScreen = LinkNewDeviceScreen()
    // AGENT-PLATFORM (decision 146): the screens the dev-stack E2E suite drives.
    static let inviteWelcomeScreen = InviteWelcomeScreen()
    static let notificationPermissionsScreen = NotificationPermissionsScreen()
    static let aiConsentPromptScreen = AIConsentPromptScreen()
    static let identityConfirmationScreen = IdentityConfirmationScreen()
    static let blockedUsersScreen = BlockedUsersScreen()
    static let yourDataScreen = YourDataScreen()
    static let deactivateAccountScreen = DeactivateAccountScreen()
    static let roomSelectionScreen = RoomSelectionScreen()
    static let interactivePostCatalogScreen = InteractivePostCatalogScreen()
    static let mediaViewer = MediaViewer() // AGENT-PLATFORM (Brief 0083, question 398)
    static let agentSpacesScreen = AgentSpacesScreen()
    static let agentDetailScreen = AgentDetailScreen()
    static let agentUsageScreen = AgentUsageScreen()
    static let agentSheetScreen = AgentSheetScreen()
    static let agentInRoomScreen = AgentInRoomScreen()
    static let addToolScreen = AddToolScreen()
    // AGENT-PLATFORM (decision 148): the coverage lane.
    static let notificationsHubScreen = NotificationsHubScreen()
    static let approvalDetailScreen = ApprovalDetailScreen()
    static let advancedSettingsScreen = AdvancedSettingsScreen()
    static let securitySettingsScreen = SecuritySettingsScreen() // AGENT-PLATFORM (decision 187)
    
    struct AlertInfo {
        let primaryButton = "alert_info-primary_button"
        let secondaryButton = "alert_info-secondary_button"
    }
    
    struct AppLockScreen {
        let cancel = "app_lock-cancel"
        func numpad(_ digit: Int) -> String {
            "app_lock-numpad_\(digit)"
        }
    }
    
    struct AppLockSetupBiometricsScreen {
        let allow = "app_lock_setup_biometrics-allow"
    }
    
    struct AppLockSetupPINScreen {
        let textField = "app_lock_setup_pin-text_field"
        let cancel = "app_lock_setup_pin-cancel"
    }
    
    struct AppLockSetupSettingsScreen {
        let changePIN = "app_lock_setup_settings-change_pin"
        let removePIN = "app_lock_setup_settings-remove_pin"
    }
    
    struct AnalyticsPromptScreen {
        let title = "analytics_prompt-title"
        let enable = "analytics_prompt-enable"
        let notNow = "analytics_prompt-not_now"
    }
    
    struct BugReportScreen {
        let report = "bug_report-report"
        let sendLogs = "bug_report-send_logs"
        let canContact = "bug_report-can_contact"
        let screenshot = "bug_report-screenshot"
        let removeScreenshot = "bug_report-remove_screenshot"
        let attachScreenshot = "bug-report-attach_screenshot"
        let cancel = "bug_report-cancel"
    }
    
    struct ChangeServer {
        let server = "change_server-server"
        let `continue` = "change_server-continue"
        let dismiss = "change_server-dismiss"
    }
    
    struct EncryptionResetScreen {
        let continueReset = "encryption_reset-continue_reset"
    }
    
    struct EncryptionResetPasswordScreen {
        let passwordField = "encryption_reset_password-password_field"
        let submit = "encryption_reset_password-submit"
    }
    
    struct HomeScreen {
        let userAvatar = "home_screen-user_avatar"
        let recoveryKeyConfirmationBannerContinue = "home_screen-recovery_key_confirmation_continue"
        let startChat = "home_screen-start_chat"
        let spaceFilters = "home_screen-space_filters"
        
        let roomNamePrefix = "home_screen-room_name"
        func roomName(_ name: String) -> String {
            "\(roomNamePrefix):\(name)"
        }
    }
    
    struct HomeTabs {
        let chats = "home_tabs-chats"
        let spaces = "home_tabs-spaces"
        let agents = "home_tabs-agents" // AGENT-PLATFORM: the Agents tab.
    }
    
    struct InviteUsersScreen {
        let proceed = "invite_users-proceed"
        let userProfile = "invite_users-user_profile"
    }
    
    struct LoginScreen {
        let emailUsername = "login-email_username"
        let password = "login-password"
        let `continue` = "login-continue"
        let unsupportedServer = "login-unsupported_server"
    }
    
    struct AuthenticationStartScreen {
        let signIn = "authentication_start-sign_in"
        let signInWithQr = "authentication_start-sign_in_with_qr"
        let appVersion = "authentication_start-app_version"
        let hidden = "authentication_start-hidden"
        // AGENT-PLATFORM (Brief 0073).
        let invitedBanner = "authentication_start-invited_banner"
        let createAccount = "authentication_start-create_account" // AGENT-PLATFORM (decision 146)
    }
    
    // AGENT-PLATFORM (Brief 0073 / ADR-0008).
    struct InvitePeopleScreen {
        let link = "invite_people-link"
        let share = "invite_people-share"
        let copy = "invite_people-copy"
        // AGENT-PLATFORM (decision 148): G5 of the dev-stack E2E suite.
        let seats = "invite_people-seats"
        func joinedUser(_ userID: String) -> String {
            "invite_people-joined:\(userID)"
        }
    }
    
    // AGENT-PLATFORM (Brief 0073 / ADR-0008).
    struct InvitePasteSheet {
        let field = "invite_paste-field"
        let use = "invite_paste-use"
        let withoutInvite = "invite_paste-without"
        let cancel = "invite_paste-cancel"
    }
    
    struct ReportContent {
        let ignoreUser = "report_content-ignore_user"
        // AGENT-PLATFORM (decision 146).
        let reason = "report_content-reason"
        let send = "report_content-send"
        let cancel = "report_content-cancel"
    }
    
    struct JoinRoomScreen {
        let join = "join-room_join"
        // AGENT-PLATFORM (decision 146): an invite cell's buttons carry the
        // cell's identifier; the invite's own screen has these.
        let acceptInvite = "join-room_accept_invite"
        let declineInvite = "join-room_decline_invite"
    }
    
    struct RoomScreen {
        let name = "room-name"
        // AGENT-PLATFORM (Brief 0073; decision 148: one per notice kind, the wire name).
        func spiralNotice(_ kind: String) -> String {
            "room-spiral_notice:\(kind)"
        }
        
        let avatar = "room-avatar"
        let attachmentPickerPhotoLibrary = "room-attachment_picker_photo_library"
        let attachmentPickerDocuments = "room-attachment_picker_documents"
        let attachmentPickerCamera = "room-attachment_picker_camera"
        let attachmentPickerLocation = "room-attachment_picker_location"
        let attachmentPickerPoll = "room-attachment_picker_poll"
        let attachmentPickerTextFormatting = "room-attachment_picker_text_formatting"
        let attachmentPickerInteractivePost = "room-attachment_picker_interactive_post" // AGENT-PLATFORM (decision 146)
        let attachmentPickerAgentTools = "room-attachment_picker_agent_tools" // AGENT-PLATFORM (decision 146)
        let timelineItemActionMenu = "room-timeline_item_action_menu"
        let joinCall = "room-join_call"
        let scrollToBottom = "room-scroll_to_bottom"
        
        let startVoiceCall = "room-start_voice_call"
        let startVideoCall = "room-start_video_call"
        
        let messageComposer = "room-message_composer"
        let sendButton = "room-send_button"
        let sendInfo = "room-send_info"
        
        let composerToolbar = ComposerToolbar()
        
        struct ComposerToolbar {
            let bold = "composer_toolbar-bold"
            let italic = "composer_toolbar-italic"
            let underline = "composer_toolbar-underline"
            let strikethrough = "composer_toolbar-strikethrough"
            let unorderedList = "composer_toolbar-unordered_list"
            let orderedList = "composer_toolbar-ordered_list"
            let indent = "composer_toolbar-indent"
            let unindent = "composer_toolbar-unindent"
            let inlineCode = "composer_toolbar-inline_code"
            let codeBlock = "composer_toolbar-code_block"
            let quote = "composer_toolbar-quote"
            let link = "composer_toolbar-link"
            let openComposeOptions = "composer_toolbar-open_compose_options"
            let closeFormattingOptions = "composer_toolbar-close-formatting-options"
        }
        
        let timelineItemActionMenuAction = TimelineItemActionMenuAction()
        
        struct TimelineItemActionMenuAction {
            let edit = "timeline_item_action_menu-edit"
            let reportContent = "timeline_item_action_menu-report_content" // AGENT-PLATFORM (decision 146)
        }
    }
    
    struct RoomDetailsScreen {
        let addTopic = "room_details-add_topic"
        let avatar = "room_details-avatar"
        let people = "room_details-people"
        let agents = "room_details-agents" // AGENT-PLATFORM (decision 192)
        let notifications = "room_details-notifications"
        let pollsHistory = "room_details-polls_history"
        let favourite = "room_details-favourite"
        // AGENT-PLATFORM (decision 146).
        let blockUser = "room_details-block_user"
        let unblockUser = "room_details-unblock_user"
        let reportRoom = "room_details-report_room"
    }
    
    struct RoomMemberDetailsScreen {
        let ignore = "room_member_details-ignore"
        let unignore = "room_member_details-unignore"
        let directChat = "room_member_details-direct_chat"
        let eraseAssistantMemory = "room_member_details-erase_assistant_memory" // AGENT-PLATFORM (Brief 0078)
    }
    
    struct RoomNotificationSettingsScreen {
        let allowCustomSetting = "room_notification_settings-allow_custom"
    }
    
    struct RoomRolesAndPermissionsScreen {
        let administrators = "room_roles_and_permissions-administrators"
        let moderators = "room_roles_and_permissions-moderators"
        let permissions = "room_roles_and_permissions-permissions"
    }
    
    struct SecureBackupScreen {
        let keyStorage = "secure_backup-key_storage"
        let recoveryKey = "secure_backup-recovery_key"
    }
    
    struct SecureBackupKeyBackupScreen {
        let deleteKeyStorage = "secure_backup_key_backup-delete_key_storage"
    }
    
    struct SecureBackupRecoveryKeyScreen {
        let generateRecoveryKey = "secure_backup_recovery_key-generate_recovery_key"
        let copyRecoveryKey = "secure_backup_recovery_key-copy_recovery_key"
        let done = "secure_backup_recovery_key-done"
        let recoveryKeyField = "secure_backup_recovery_key-recovery_key_field"
        let confirm = "secure_backup_recovery_key-confirm"
    }
    
    struct ServerConfirmationScreen {
        let `continue` = "server_confirmation-continue"
        let changeServer = "server_confirmation-change_server"
        let serverPicker = "server_confirmation-server_picker"
    }
    
    struct SessionVerificationScreen {
        let acceptVerificationRequest = "session_verification-accept_verification_request"
        let ignoreVerificationRequest = "session_verification-ignore_verification_request"
        let requestVerification = "session_verification-request_verification"
        let acceptChallenge = "session_verification-accept_challenge"
        let declineChallenge = "session_verification-decline_challenge"
        let emojiWrapper = "session_verification-emojis"
        let verificationComplete = "session_verification-verification_complete"
    }
    
    struct SettingsScreen {
        let invitePeople = "settings-invite_people" // AGENT-PLATFORM (Brief 0073).
        let security = "settings-security" // AGENT-PLATFORM (decision 187).
        let privacy = "settings-privacy" // AGENT-PLATFORM (decision 187).
        let yourData = "settings-your_data" // AGENT-PLATFORM (decision 146).
        let appearanceAndMedia = "settings-appearance_and_media" // AGENT-PLATFORM (decision 187).
        let deleteAccount = "settings-delete_account" // AGENT-PLATFORM (decision 146).
        let account = "settings-account"
        let addAccount = "settings-add_account"
        let secureBackup = "settings-secure_backup"
        let notifications = "settings-notifications"
        let analytics = "settings-analytics"
        let reportBug = "settings-report_bug"
        let about = "settings_about"
        let developerOptions = "settings_developer-options"
        let logout = "settings-logout"
    }
    
    // AGENT-PLATFORM (decision 187).
    struct SecuritySettingsScreen {
        let newPhrase = "security_settings-new_phrase"
        let devices = "security_settings-devices"
        let encryption = "security_settings-encryption"
        let screenLock = "security_settings-screen_lock"
    }
    
    struct SoftLogoutScreen {
        let title = "soft_logout-title"
        let message = "soft_logout-message"
        let password = "soft_logout-password"
        let forgotPassword = "soft_logout-forgot_password"
        let next = "soft_logout-next"
        let clearDataTitle = "soft_logout-clear_data_title"
        let clearDataMessage = "soft_logout-clear_data_message"
        let clearData = "soft_logout-clear_data"
    }
    
    struct StartChatScreen {
        let closeStartChat = "start_chat-close"
        let createRoom = "start_chat-create_room"
        let inviteFriends = "start_chat-invite_friends"
        let joinedViaInvite = "start_chat-joined_via_invite" // AGENT-PLATFORM (Brief 0073).
        let searchNoResults = "start_chat-search_no_results"
    }
    
    struct CreateRoomScreen {
        let create = "create_room-create"
        let cancel = "create_room-cancel"
        let roomAvatar = "create_room-room_avatar"
        let roomName = "create_room-room_name"
        let roomTopic = "create_room-room_topic"
        let mediaPicker = "create_room-media_picker"
        let filePicker = "create_room-file_picker"
    }
    
    struct PollFormScreen {
        let addOption = "poll_form-add_option"
        let maxSelections = "poll_form-max_selections"
        let maxSelectionsDecrement = "poll_form-max_selections-decrement"
        let maxSelectionsIncrement = "poll_form-max_selections-increment"
        let pollKind = "poll_form-kind"
        let question = "poll_form-question"
        let submit = "poll_form-submit"
        
        private let optionPrefix = "poll_form-option"
        func optionID(_ index: Int) -> String {
            "\(optionPrefix)-\(index)"
        }
    }
    
    struct NotificationSettingsScreen {
        let fixMismatchConfiguration = "notification_settings_screen-fix_mismatch_configuration"
    }
    
    struct NotificationSettingsEditScreen {
        let roomNamePrefix = "notification_settings_edit_screen-room_name"
        func roomName(_ name: String) -> String {
            "\(roomNamePrefix):\(name)"
        }
    }
    
    struct RoomPollsHistoryScreen {
        let loadMore = "room_polls_history_screen-load_more"
    }
    
    struct RoomMembersListScreen {
        let invite = "room_members_list_screen-invite"
        
        let roomMemberPrefix = "room_members_list_screen-member"
        func member(_ userID: String) -> String {
            "\(roomMemberPrefix):\(userID)"
        }
    }
    
    struct ManageRoomMemberSheet {
        let viewProfile = "manage_room_member_sheet-view_profile"
    }
    
    struct SpacesScreen {
        let roomNamePrefix = "spaces_screen-room_name"
        func spaceRoomName(_ name: String) -> String {
            "\(roomNamePrefix):\(name)"
        }
    }
    
    struct SpaceScreen {
        let moreMenu = "space_screen-more_menu"
    }
    
    struct SpaceAddRoomsScreen {
        let cancel = "space_add_rooms_screen-cancel"
    }
    
    struct SearchScreen {
        let roomNamePrefix = "search_screen-room_name"
        func roomName(_ name: String) -> String {
            "\(roomNamePrefix):\(name)"
        }
    }
    
    struct SpaceSettingsScreen {
        let editBaseInfo = "space_settings_screen-edit_space_info"
    }
    
    struct LinkNewDeviceScreen {
        let cancel = "link_new_device_screen-cancel"
        let mobileDevice = "link_new_device_screen-mobile_device"
        let desktopComputer = "link_new_device_screen-desktop_computer"
    }
    
    // MARK: AGENT-PLATFORM (decision 146): the dev-stack E2E suite.
    
    struct InviteWelcomeScreen {
        let text = "invite_welcome-text" // decision 148: G5
        let message = "invite_welcome-message"
        let later = "invite_welcome-later"
    }
    
    struct NotificationPermissionsScreen {
        let enable = "notification_permissions-enable"
        let notNow = "notification_permissions-not_now"
    }
    
    struct AIConsentPromptScreen {
        let allow = "ai_consent_prompt-allow"
        let notNow = "ai_consent_prompt-not_now"
    }
    
    struct IdentityConfirmationScreen {
        /// The Debug build's skip: a dev password account has a cross-signing
        /// identity and no other device to confirm this one.
        let skip = "identity_confirmation-skip"
    }
    
    struct BlockedUsersScreen {
        func user(_ userID: String) -> String {
            "blocked_users-user:\(userID)"
        }
    }
    
    struct YourDataScreen {
        let exportAccount = "your_data-export_account"
    }
    
    struct DeactivateAccountScreen {
        let delete = "deactivate_account-delete"
    }
    
    struct RoomSelectionScreen {
        let confirm = "room_selection-confirm"
        func room(_ name: String) -> String {
            "room_selection-room:\(name)"
        }
    }
    
    struct MediaViewer {
        let info = "media_viewer-info"
    }
    
    struct InteractivePostCatalogScreen {
        let yours = "interactive_catalog-yours"
        let search = "interactive_catalog-search"
        let noResults = "interactive_catalog-no_results"
        let pagePosition = "interactive_catalog-page_position"
        let introductionDone = "interactive_catalog-introduction_done"
        let newCard = "interactive_catalog-new_card"
        let newDots = "interactive_catalog-new_dots"
        let facts = "interactive_catalog-facts"
        let describeNew = "interactive_catalog-describe_new"
        let currentTitle = "interactive_catalog-current_title"
        let fillIn = "interactive_catalog-fill_in"
        let publish = "interactive_catalog-publish"
        let changeFirst = "interactive_catalog-change_first"
        let assistantNote = "interactive_catalog-assistant_note"
        let createAgent = "interactive_catalog-create_agent"
        let retryAgents = "interactive_catalog-retry_agents"
        let cancel = "interactive_catalog-cancel"

        func card(_ templateID: String) -> String {
            "interactive_catalog-card:\(templateID)"
        }

        func section(_ sectionID: String) -> String {
            "interactive_catalog-section:\(sectionID)"
        }
    }
    
    struct AgentSpacesScreen {
        /// A load failure, on any agent-spaces screen that shows one.
        let error = "agent_spaces-error"
        let approvalsBell = "agent_spaces-approvals_bell" // AGENT-PLATFORM (decision 148)
        let addMenu = "agent_spaces-add_menu"
        let newCompany = "agent_spaces-new_company"
        /// A space's section header.
        func space(_ orgID: String) -> String {
            "agent_spaces-space:\(orgID)"
        }
        
        func editCompany(_ orgID: String) -> String {
            "agent_spaces-edit_company:\(orgID)"
        }
        
        func newAgent(_ orgID: String) -> String {
            "agent_spaces-new_agent:\(orgID)"
        }
        
        func agent(_ matrixUserID: String) -> String {
            "agent_spaces-agent:\(matrixUserID)"
        }
    }
    
    struct AgentDetailScreen {
        let message = "agent_detail-message"
        let addToChat = "agent_detail-add_to_chat"
        let activity = "agent_detail-activity"
        let usage = "agent_detail-usage"
        let edit = "agent_detail-edit"
        // Archive is for role agents only (decision 153).
        let archive = "agent_detail-archive"
    }
    
    struct AgentUsageScreen {
        let week = "agent_usage-week"
    }
    
    struct AgentSheetScreen {
        let addAgent = "agent_sheet-add_agent"
        let addTool = "agent_sheet-add_tool"
        func agent(_ matrixUserID: String) -> String {
            "agent_sheet-agent:\(matrixUserID)"
        }
        
        func agentMenu(_ matrixUserID: String) -> String {
            "agent_sheet-agent_menu:\(matrixUserID)"
        }
        
        func tool(_ id: String) -> String {
            "agent_sheet-tool:\(id)"
        }
        
        func quickAdd(_ kind: String) -> String {
            "agent_sheet-quick_add:\(kind)"
        }
    }
    
    struct AgentInRoomScreen {
        let openChat = "agent_in_room-open_chat"
        let addTool = "agent_in_room-add_tool"
        let remove = "agent_in_room-remove"
    }
    
    struct AddToolScreen {
        func kind(_ kind: String) -> String {
            "add_tool-kind:\(kind)"
        }
    }
    
    // MARK: AGENT-PLATFORM (decision 148): the coverage lane.
    
    struct NotificationsHubScreen {
        /// A pinned "needs action" row, by its approval's or verification's id.
        func item(_ subjectID: String) -> String {
            "notifications_hub-item:\(subjectID)"
        }
        
        /// A row of the activity feed, by its audit row's id.
        func activity(_ id: String) -> String {
            "notifications_hub-activity:\(id)"
        }
    }
    
    struct ApprovalDetailScreen {
        /// The card's banner: `first_contact`, `cold_outreach` or `block_request`.
        func kind(_ kind: String) -> String {
            "approval_detail-kind:\(kind)"
        }
        
        let approve = "approval_detail-approve"
        let edit = "approval_detail-edit"
        let reject = "approval_detail-reject"
        let draftField = "approval_detail-draft_field"
        let save = "approval_detail-save"
        let cancelEdit = "approval_detail-cancel_edit"
        let block = "approval_detail-block"
        let dontBlock = "approval_detail-dont_block"
        let done = "approval_detail-done"
    }
    
    struct AdvancedSettingsScreen {
        let aiConsent = "advanced_settings-ai_consent"
        let aiConsentRetry = "advanced_settings-ai_consent_retry" // AGENT-PLATFORM (decision 150)
        let blockedUsers = "advanced_settings-blocked_users" // AGENT-PLATFORM (decision 187)
    }
}
