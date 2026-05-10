Function Invoke-AddSensitivityLabel {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitivityLabel.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

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

    $RawParams = $Request.Body.PowerShellCommand | ConvertFrom-Json
    $PolicyParams = $RawParams.PolicyParams

    $LabelParams = Format-CIPPCompliancePolicyParams -Source $RawParams -AllowedFields $LabelAllowedFields

    $Tenants = ($Request.Body.selectedTenants).value
    $Result = foreach ($TenantFilter in $Tenants) {
        try {
            $ExistingLabels = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Label' -Compliance | Select-Object Name, DisplayName } catch { @() }
            $ExistingLabelPolicies = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-LabelPolicy' -Compliance | Select-Object Name } catch { @() }

            $LabelExists = [bool]($ExistingLabels | Where-Object { $_.Name -eq $LabelParams.Name -or $_.DisplayName -eq $LabelParams.Name })

            if ($LabelExists) {
                $SetParams = @{} + $LabelParams
                $SetParams.Remove('Name')
                $SetParams['Identity'] = $LabelParams.Name
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Label' -cmdParams $SetParams -Compliance -useSystemMailbox $true
                $LabelAction = "Updated sensitivity label $($LabelParams.Name) in $TenantFilter."
            } else {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-Label' -cmdParams $LabelParams -Compliance -useSystemMailbox $true
                $LabelAction = "Created sensitivity label $($LabelParams.Name) in $TenantFilter."
            }

            if ($PolicyParams) {
                $PolicyHash = Format-CIPPCompliancePolicyParams -Source $PolicyParams -AllowedFields $PolicyAllowedFields
                if (-not $PolicyHash.ContainsKey('Labels') -or -not $PolicyHash['Labels']) {
                    $PolicyHash['Labels'] = @($LabelParams.Name)
                }
                $PolicyName = if ($PolicyHash.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace([string]$PolicyHash['Name'])) {
                    $PolicyHash['Name']
                } else {
                    "$($LabelParams.Name) Policy"
                }
                $PolicyHash['Name'] = $PolicyName

                $LabelPolicyExists = [bool]($ExistingLabelPolicies | Where-Object { $_.Name -eq $PolicyName })

                if ($LabelPolicyExists) {
                    # Set-LabelPolicy uses Add{Location}/Remove{Location} pairs and AddLabels/RemoveLabels.
                    $LabelPolicyAddPrefixed = @('Labels') + ($PolicyAllowedFields | Where-Object { $_ -like '*Location*' })
                    $SetPolicyHash = @{}
                    foreach ($key in $PolicyHash.Keys) {
                        if ($key -eq 'Name') { continue }
                        $targetKey = if ($key -in $LabelPolicyAddPrefixed) { "Add$key" } else { $key }
                        $SetPolicyHash[$targetKey] = $PolicyHash[$key]
                    }
                    $SetPolicyHash['Identity'] = $PolicyName
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-LabelPolicy' -cmdParams $SetPolicyHash -Compliance -useSystemMailbox $true
                } else {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-LabelPolicy' -cmdParams $PolicyHash -Compliance -useSystemMailbox $true
                }
            }

            $LabelAction
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $LabelAction -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not deploy sensitivity label for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not deploy sensitivity label for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
