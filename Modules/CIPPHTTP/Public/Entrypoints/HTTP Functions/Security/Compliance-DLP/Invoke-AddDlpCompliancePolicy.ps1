Function Invoke-AddDlpCompliancePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.DlpCompliancePolicy.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

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

    $RawParams = $Request.Body.PowerShellCommand | ConvertFrom-Json
    $RuleParams = $RawParams.RuleParams

    $RequestParams = Format-CIPPCompliancePolicyParams -Source $RawParams -AllowedFields $PolicyAllowedFields -LocationFields $LocationFields

    $Tenants = ($Request.Body.selectedTenants).value
    $Result = foreach ($TenantFilter in $Tenants) {
        try {
            $ExistingPolicies = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpCompliancePolicy' -Compliance | Select-Object Name } catch { @() }
            $ExistingRules = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpComplianceRule' -Compliance | Select-Object Name, ParentPolicyName } catch { @() }

            $PolicyExists = [bool]($ExistingPolicies | Where-Object { $_.Name -eq $RequestParams.Name })

            if ($PolicyExists) {
                $SetParams = @{} + $RequestParams
                $SetParams.Remove('Name')
                $SetParams['Identity'] = $RequestParams.Name
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DlpCompliancePolicy' -cmdParams $SetParams -Compliance -useSystemMailbox $true
                $PolicyAction = "Updated DLP compliance policy $($RequestParams.Name) in $TenantFilter."
            } else {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DlpCompliancePolicy' -cmdParams $RequestParams -Compliance -useSystemMailbox $true
                $PolicyAction = "Created DLP compliance policy $($RequestParams.Name) in $TenantFilter."
            }

            if ($RuleParams) {
                $RuleHash = Format-CIPPCompliancePolicyParams -Source $RuleParams -AllowedFields $RuleAllowedFields
                $RuleHash['Policy'] = $RequestParams.Name
                $RuleName = if ($RuleHash.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace([string]$RuleHash['Name'])) {
                    $RuleHash['Name']
                } else {
                    "$($RequestParams.Name) Rule"
                }
                $RuleHash['Name'] = $RuleName

                $RuleExists = [bool]($ExistingRules | Where-Object { $_.Name -eq $RuleName -or $_.ParentPolicyName -eq $RequestParams.Name })

                if ($RuleExists) {
                    $SetRuleHash = @{} + $RuleHash
                    $SetRuleHash.Remove('Name')
                    $SetRuleHash.Remove('Policy')
                    $SetRuleHash['Identity'] = $RuleName
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DlpComplianceRule' -cmdParams $SetRuleHash -Compliance -useSystemMailbox $true
                } else {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DlpComplianceRule' -cmdParams $RuleHash -Compliance -useSystemMailbox $true
                }
            }

            $PolicyAction
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $PolicyAction -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not deploy DLP compliance policy for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not deploy DLP compliance policy for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
