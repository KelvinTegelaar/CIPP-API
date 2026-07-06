function Get-CIPPDlpComplianceFieldList {
    <#
    .SYNOPSIS
        Single source of truth for the DLP compliance policy/rule cmdlet parameter allowlists.
    .DESCRIPTION
        The New-/Set-DlpCompliancePolicy and New-/Set-DlpComplianceRule cmdlets accept only a subset of
        the (much larger) set of properties Get-* returns. These allowlists are shared by every code path
        that builds or compares DLP policy params - template creation, deploy, and drift comparison - so
        the accepted fields never diverge between them (divergence here previously caused 'Mode'/'Priority'
        being sent where invalid, etc.).

        Priority is intentionally excluded: Microsoft assigns it per tenant from existing policy ordering,
        so it varies between tenants and must not be captured into, deployed from, or drift-compared.
    .OUTPUTS
        PSCustomObject with Policy, Rule, and Location (subset of Policy) string arrays.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Policy = @(
        'Name', 'Comment', 'Mode',
        'ExchangeLocation', 'ExchangeLocationException',
        'SharePointLocation', 'SharePointLocationException',
        'OneDriveLocation', 'OneDriveLocationException',
        'TeamsLocation', 'TeamsLocationException',
        'EndpointDlpLocation', 'EndpointDlpLocationException',
        'OnPremisesScannerDlpLocation', 'OnPremisesScannerDlpLocationException',
        'ThirdPartyAppDlpLocation', 'ThirdPartyAppDlpLocationException',
        'PowerBIDlpLocation', 'PowerBIDlpLocationException',
        'ModernGroupLocation', 'ModernGroupLocationException'
    )

    # Note: DLP rules have no 'Mode' parameter (that is policy-level). 'Policy' is the parent reference
    # added at deploy time; it is not a comparable setting.
    $Rule = @(
        'Name', 'Policy', 'Comment', 'Disabled',
        'ContentContainsSensitiveInformation', 'ExceptIfContentContainsSensitiveInformation',
        'ContentPropertyContainsWords', 'BlockAccess', 'BlockAccessScope',
        'NotifyUser', 'NotifyEmailCustomText', 'NotifyEmailCustomSubject',
        'NotifyPolicyTipCustomText', 'GenerateAlert', 'AlertProperties',
        'GenerateIncidentReport', 'IncidentReportContent',
        'AccessScope', 'From', 'FromMemberOf', 'FromAddressContainsWords',
        'FromAddressMatchesPatterns', 'SentTo', 'SentToMemberOf',
        'RecipientDomainIs', 'AnyOfRecipientAddressContainsWords',
        'AnyOfRecipientAddressMatchesPatterns', 'AnyOfRecipientAddressDomainIs',
        'ExceptIfFrom', 'ExceptIfFromMemberOf', 'ExceptIfFromAddressContainsWords',
        'ExceptIfFromAddressMatchesPatterns',
        'AddRecipients', 'BlockMessage', 'GenerateAlertOn', 'IncidentReportTo',
        'ReportSeverityLevel', 'RuleErrorAction',
        'ContentExtensionMatchesWords', 'DocumentNameMatchesPatterns',
        'DocumentNameMatchesWords', 'DocumentSizeOver',
        'ContentCharacterSetContainsWords', 'ContentFileTypeMatches'
    )

    return [pscustomobject]@{
        Policy   = $Policy
        Rule     = $Rule
        Location = @($Policy | Where-Object { $_ -like '*Location*' })
        # Valid -Mode input values for New-/Set-DlpCompliancePolicy. Transient/output-only states such as
        # 'PendingDeletion' are NOT accepted as input and must be dropped before deploy.
        ValidPolicyModes = @('Enable', 'TestWithNotifications', 'TestWithoutNotifications', 'Disable')
    }
}
