function Get-CIPPSensitivityLabelField {
    <#
    .SYNOPSIS
        Returns the valid New-Label / Set-Label parameter names CIPP supports for sensitivity label deployment.
    .DESCRIPTION
        Single source of truth for the sensitivity label field allowlist, shared by Set-CIPPSensitivityLabel
        (deploy) and Invoke-AddSensitivityLabelTemplate (capture keep-list) so the two cannot drift.

        Names match the Microsoft Purview New-Label/Set-Label cmdlet parameters exactly. Note the content
        marking and watermark parameters are all 'Apply'-prefixed (ApplyContentMarkingHeaderText,
        ApplyWaterMarkingText, ...) - the bare 'ContentMarking*' names do not exist and cause an
        AmbiguousParameterSetException.

        'Priority' is included here but is only valid on Set-Label, not New-Label - Set-CIPPSensitivityLabel
        applies it via a dedicated Set-Label call. 'Disabled' is intentionally absent because it is not a
        valid parameter on either cmdlet.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    return @(
        # Core
        'Name', 'DisplayName', 'Comment', 'Tooltip', 'ParentId', 'ContentType', 'Priority',
        'Conditions', 'LocaleSettings', 'Settings', 'AdvancedSettings',

        # Encryption
        'EncryptionEnabled', 'EncryptionProtectionType',
        'EncryptionTemplateId', 'EncryptionLinkedTemplateId', 'EncryptionAipTemplateScopes',
        'EncryptionRightsDefinitions', 'EncryptionContentExpiredOnDateInDaysOrNever',
        'EncryptionDoNotForward', 'EncryptionEncryptOnly', 'EncryptionPromptUser',
        'EncryptionOfflineAccessDays',

        # Content marking - header
        'ApplyContentMarkingHeaderEnabled', 'ApplyContentMarkingHeaderText',
        'ApplyContentMarkingHeaderFontSize', 'ApplyContentMarkingHeaderFontColor',
        'ApplyContentMarkingHeaderFontName', 'ApplyContentMarkingHeaderAlignment',
        'ApplyContentMarkingHeaderMargin',

        # Content marking - footer
        'ApplyContentMarkingFooterEnabled', 'ApplyContentMarkingFooterText',
        'ApplyContentMarkingFooterFontSize', 'ApplyContentMarkingFooterFontColor',
        'ApplyContentMarkingFooterFontName', 'ApplyContentMarkingFooterAlignment',
        'ApplyContentMarkingFooterMargin',

        # Watermark
        'ApplyWaterMarkingEnabled', 'ApplyWaterMarkingText',
        'ApplyWaterMarkingFontSize', 'ApplyWaterMarkingFontColor',
        'ApplyWaterMarkingFontName', 'ApplyWaterMarkingLayout',

        # Site & group protection
        'SiteAndGroupProtectionEnabled', 'SiteAndGroupProtectionPrivacy',
        'SiteAndGroupProtectionLevel',
        'SiteAndGroupProtectionAllowAccessToGuestUsers',
        'SiteAndGroupProtectionAllowEmailFromGuestUsers',
        'SiteAndGroupProtectionAllowFullAccess',
        'SiteAndGroupProtectionAllowLimitedAccess',
        'SiteAndGroupProtectionBlockAccess'
    )
}
