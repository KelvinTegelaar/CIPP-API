function Set-CIPPSensitivityLabel {
    <#
    .SYNOPSIS
        Deploy or update a single sensitivity label (+ optional label policy) in a tenant from a template object.
    .DESCRIPTION
        Single source of truth for sensitivity label deployment, shared by the HTTP deploy endpoint and
        the standard.
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

    $LabelAllowedFields = @(
        'Name', 'DisplayName', 'Comment', 'Tooltip', 'ParentId',
        'Disabled', 'ContentType', 'Priority',
        'EncryptionEnabled', 'EncryptionProtectionType', 'EncryptionRightsDefinitions',
        'EncryptionContentExpiredOnDateInDaysOrNever', 'EncryptionDoNotForward',
        'EncryptionEncryptOnly', 'EncryptionOfflineAccessDays',
        'EncryptionPromptUser', 'EncryptionAESKeySize',
        'ContentMarkingHeaderEnabled', 'ContentMarkingHeaderText',
        'ContentMarkingHeaderFontSize', 'ContentMarkingHeaderFontColor', 'ContentMarkingHeaderAlignment',
        'ContentMarkingFooterEnabled', 'ContentMarkingFooterText',
        'ContentMarkingFooterFontSize', 'ContentMarkingFooterFontColor', 'ContentMarkingFooterAlignment',
        'ContentMarkingFooterMargin',
        'ContentMarkingWatermarkEnabled', 'ContentMarkingWatermarkText',
        'ContentMarkingWatermarkFontSize', 'ContentMarkingWatermarkFontColor', 'ContentMarkingWatermarkLayout',
        'ApplyContentMarkingHeaderEnabled', 'ApplyContentMarkingFooterEnabled', 'ApplyWaterMarkingEnabled',
        'SiteAndGroupProtectionEnabled', 'SiteAndGroupProtectionPrivacy',
        'SiteAndGroupProtectionAllowAccessToGuestUsers',
        'SiteAndGroupProtectionAllowEmailFromGuestUsers',
        'SiteAndGroupProtectionAllowFullAccess',
        'SiteAndGroupProtectionAllowLimitedAccess',
        'SiteAndGroupProtectionBlockAccess',
        'Conditions', 'AdvancedSettings', 'Settings', 'LocaleSettings'
    )
    $PolicyAllowedFields = @(
        'Name', 'Comment', 'Labels', 'AdvancedSettings', 'Settings',
        'ExchangeLocation', 'ExchangeLocationException',
        'SharePointLocation', 'SharePointLocationException',
        'OneDriveLocation', 'OneDriveLocationException',
        'ModernGroupLocation', 'ModernGroupLocationException',
        'PolicyTemplateInfo'
    )
    $PolicyLocationFields = $PolicyAllowedFields | Where-Object { $_ -like '*Location*' }
    $LabelPolicyAddPrefixed = @('Labels') + $PolicyLocationFields

    $LabelParams = Format-CIPPCompliancePolicyParams -Source $Template -AllowedFields $LabelAllowedFields
    $PolicySource = $Template.PolicyParams
    $LabelName = $LabelParams.Name

    try {
        $ExistingLabels = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Label' -Compliance | Select-Object Name, DisplayName } catch { @() }
        $ExistingLabelPolicies = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-LabelPolicy' -Compliance | Select-Object Name } catch { @() }

        $LabelExists = [bool]($ExistingLabels | Where-Object { $_.Name -eq $LabelName -or $_.DisplayName -eq $LabelName })

        if ($LabelExists) {
            $SetParams = ConvertTo-CIPPComplianceSetParams -Params $LabelParams -Identity $LabelName
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Label' -cmdParams $SetParams -Compliance -useSystemMailbox $true
            $LabelAction = "Updated sensitivity label '$LabelName' in $TenantFilter."
        } else {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-Label' -cmdParams $LabelParams -Compliance -useSystemMailbox $true
            $LabelAction = "Created sensitivity label '$LabelName' in $TenantFilter."
        }

        if ($PolicySource) {
            $PolicyHash = Format-CIPPCompliancePolicyParams -Source $PolicySource -AllowedFields $PolicyAllowedFields
            if (-not $PolicyHash.ContainsKey('Labels') -or -not $PolicyHash['Labels']) {
                $PolicyHash['Labels'] = @($LabelName)
            }
            $PolicyName = if ($PolicyHash.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace([string]$PolicyHash['Name'])) {
                $PolicyHash['Name']
            } else {
                "$LabelName Policy"
            }
            $PolicyHash['Name'] = $PolicyName

            $LabelPolicyExists = [bool]($ExistingLabelPolicies | Where-Object { $_.Name -eq $PolicyName })

            if ($LabelPolicyExists) {
                $SetPolicyHash = ConvertTo-CIPPComplianceSetParams -Params $PolicyHash -Identity $PolicyName -AddPrefixFields $LabelPolicyAddPrefixed
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-LabelPolicy' -cmdParams $SetPolicyHash -Compliance -useSystemMailbox $true
            } else {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-LabelPolicy' -cmdParams $PolicyHash -Compliance -useSystemMailbox $true
            }
        }

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $LabelAction -sev Info
        return $LabelAction
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $msg = "Could not deploy sensitivity label '$LabelName' to $($TenantFilter): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Error -LogData $ErrorMessage
        return $msg
    }
}
