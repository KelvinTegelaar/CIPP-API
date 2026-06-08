function Set-CIPPDlpCompliancePolicy {
    <#
    .SYNOPSIS
        Deploy or update a single DLP compliance policy (+ optional rule) in a tenant from a template object.
    .DESCRIPTION
        Single source of truth for deploying DLP compliance policies. Both the HTTP deploy endpoint
        (Invoke-AddDlpCompliancePolicy) and the standard (Invoke-CIPPStandardDlpCompliancePolicyTemplate)
        call into this so the deploy logic, allowlists, location normalization, Set-vs-New decision, and
        built-in skip behavior all live in one place.
    .PARAMETER TenantFilter
        Target tenant (defaultDomainName or customerId).
    .PARAMETER Template
        Source template object — typically the JSON from a stored template or a PowerShellCommand body,
        already parsed with ConvertFrom-Json.
    .PARAMETER APIName
        Caller's API name, used for log messages.
    .PARAMETER Headers
        Optional request headers, used for log messages on HTTP-driven calls.
    .OUTPUTS
        String result message describing what happened (Created / Updated / Skipped / Failed ...).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TenantFilter,
        [Parameter(Mandatory)] $Template,
        [Parameter(Mandatory)] [string] $APIName,
        $Headers
    )

    $PolicyAllowedFields = @(
        'Name', 'Comment', 'Mode', 'Priority',
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
    $RuleAllowedFields = @(
        'Name', 'Policy', 'Comment', 'Disabled', 'Mode', 'Priority',
        'ContentContainsSensitiveInformation',
        'ContentPropertyContainsWords', 'BlockAccess', 'BlockAccessScope',
        'NotifyUser', 'NotifyEmailCustomText', 'NotifyEmailCustomSubject',
        'NotifyPolicyTipCustomText', 'GenerateAlert', 'AlertProperties',
        'GenerateIncidentReport', 'IncidentReportContent',
        'ExceptIfContentContainsSensitiveInformation',
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
    $LocationFields = $PolicyAllowedFields | Where-Object { $_ -like '*Location*' }

    $PolicyParams = Format-CIPPCompliancePolicyParams -Source $Template -AllowedFields $PolicyAllowedFields -LocationFields $LocationFields
    $RuleSource = $Template.RuleParams
    $PolicyName = $PolicyParams.Name

    try {
        $ExistingPolicies = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpCompliancePolicy' -Compliance | Select-Object Name, IsDefault } catch { @() }
        $ExistingRules = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpComplianceRule' -Compliance | Select-Object Name, ParentPolicyName } catch { @() }

        $ExistingPolicy = $ExistingPolicies | Where-Object { $_.Name -eq $PolicyName } | Select-Object -First 1
        if ($ExistingPolicy -and $ExistingPolicy.IsDefault) {
            $msg = "DLP compliance policy '$PolicyName' is a Microsoft built-in and cannot be modified — skipping in $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Warning
            return $msg
        }

        if ($ExistingPolicy) {
            $SetParams = ConvertTo-CIPPComplianceSetParams -Params $PolicyParams -Identity $PolicyName -AddPrefixFields $LocationFields
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DlpCompliancePolicy' -cmdParams $SetParams -Compliance -useSystemMailbox $true
            $PolicyAction = "Updated DLP compliance policy '$PolicyName' in $TenantFilter."
        } else {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DlpCompliancePolicy' -cmdParams $PolicyParams -Compliance -useSystemMailbox $true
            $PolicyAction = "Created DLP compliance policy '$PolicyName' in $TenantFilter."
        }

        if ($RuleSource) {
            $RuleHash = Format-CIPPCompliancePolicyParams -Source $RuleSource -AllowedFields $RuleAllowedFields
            $RuleHash['Policy'] = $PolicyName
            $RuleName = if ($RuleHash.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace([string]$RuleHash['Name'])) {
                $RuleHash['Name']
            } else {
                "$PolicyName Rule"
            }
            $RuleHash['Name'] = $RuleName

            $RuleExists = [bool]($ExistingRules | Where-Object { $_.Name -eq $RuleName -or $_.ParentPolicyName -eq $PolicyName })

            if ($RuleExists) {
                $SetRuleHash = ConvertTo-CIPPComplianceSetParams -Params $RuleHash -Identity $RuleName
                $SetRuleHash.Remove('Policy') | Out-Null
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DlpComplianceRule' -cmdParams $SetRuleHash -Compliance -useSystemMailbox $true
            } else {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DlpComplianceRule' -cmdParams $RuleHash -Compliance -useSystemMailbox $true
            }
        }

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $PolicyAction -sev Info
        return $PolicyAction
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $msg = "Could not deploy DLP compliance policy '$PolicyName' to $($TenantFilter): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Error -LogData $ErrorMessage
        return $msg
    }
}
