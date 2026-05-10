Function Invoke-AddRetentionCompliancePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.RetentionCompliancePolicy.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $PolicyAllowedFields = @(
        'Name', 'Comment', 'Enabled', 'RestrictiveRetention',
        'ExchangeLocation', 'ExchangeLocationException',
        'SharePointLocation', 'SharePointLocationException',
        'OneDriveLocation', 'OneDriveLocationException',
        'ModernGroupLocation', 'ModernGroupLocationException',
        'TeamsChannelLocation', 'TeamsChannelLocationException',
        'TeamsChatLocation', 'TeamsChatLocationException',
        'PublicFolderLocation',
        'SkypeLocation', 'SkypeLocationException'
    )

    $RuleAllowedFields = @(
        'Name', 'Policy', 'Comment',
        'RetentionDuration', 'RetentionComplianceAction',
        'ExpirationDateOption', 'PublishComplianceTag',
        'ApplyComplianceTag', 'ContentMatchQuery',
        'ContentDateFrom', 'ContentDateTo'
    )

    $LocationFields = $PolicyAllowedFields | Where-Object { $_ -like '*Location*' }

    $RawParams = $Request.Body.PowerShellCommand | ConvertFrom-Json
    $RuleParams = $RawParams.RuleParams

    $RequestParams = Format-CIPPCompliancePolicyParams -Source $RawParams -AllowedFields $PolicyAllowedFields -LocationFields $LocationFields

    $Tenants = ($Request.Body.selectedTenants).value
    $Result = foreach ($TenantFilter in $Tenants) {
        try {
            $ExistingPolicies = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionCompliancePolicy' -Compliance -AsApp | Select-Object Name } catch { @() }
            $ExistingRules = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionComplianceRule' -Compliance -AsApp | Select-Object Name, Policy } catch { @() }

            $PolicyExists = [bool]($ExistingPolicies | Where-Object { $_.Name -eq $RequestParams.Name })

            if ($PolicyExists) {
                # Set-RetentionCompliancePolicy uses Add{Location}/Remove{Location} pairs instead of accepting
                # the direct location params. Convert here so an overwrite redeploy goes through cleanly.
                $SetParams = @{}
                foreach ($key in $RequestParams.Keys) {
                    if ($key -eq 'Name') { continue }
                    $targetKey = if ($key -in $LocationFields) { "Add$key" } else { $key }
                    $SetParams[$targetKey] = $RequestParams[$key]
                }
                $SetParams['Identity'] = $RequestParams.Name
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-RetentionCompliancePolicy' -cmdParams $SetParams -Compliance -AsApp -useSystemMailbox $true
                $PolicyAction = "Updated retention compliance policy $($RequestParams.Name) in $TenantFilter."
            } else {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-RetentionCompliancePolicy' -cmdParams $RequestParams -Compliance -AsApp -useSystemMailbox $true
                $PolicyAction = "Created retention compliance policy $($RequestParams.Name) in $TenantFilter."
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

                $RuleExists = [bool]($ExistingRules | Where-Object { $_.Name -eq $RuleName -or $_.Policy -eq $RequestParams.Name })

                if ($RuleExists) {
                    $SetRuleHash = @{} + $RuleHash
                    $SetRuleHash.Remove('Name')
                    $SetRuleHash.Remove('Policy')
                    $SetRuleHash['Identity'] = $RuleName
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-RetentionComplianceRule' -cmdParams $SetRuleHash -Compliance -AsApp -useSystemMailbox $true
                } else {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-RetentionComplianceRule' -cmdParams $RuleHash -Compliance -AsApp -useSystemMailbox $true
                }
            }

            $PolicyAction
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $PolicyAction -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not deploy Retention compliance policy for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not deploy Retention compliance policy for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
