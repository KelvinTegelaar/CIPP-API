function Set-CIPPRetentionCompliancePolicy {
    <#
    .SYNOPSIS
        Deploy or update a single retention compliance policy (+ optional rule) in a tenant from a template object.
    .DESCRIPTION
        Single source of truth for retention deployment. Both the HTTP deploy endpoint and the standard
        call this so allowlists, location handling, and Set-vs-New decisions live in one place. Uses
        -AsApp for the IPPS calls since retention cmdlets typically aren't reachable through GDAP
        delegated identities.
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

    $PolicyParams = Format-CIPPCompliancePolicyParams -Source $Template -AllowedFields $PolicyAllowedFields -LocationFields $LocationFields
    $RuleSource = $Template.RuleParams
    $PolicyName = $PolicyParams.Name

    try {
        $ExistingPolicies = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionCompliancePolicy' -Compliance -AsApp | Select-Object Name } catch { @() }
        $ExistingRules = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionComplianceRule' -Compliance -AsApp | Select-Object Name, Policy } catch { @() }

        $PolicyExists = [bool]($ExistingPolicies | Where-Object { $_.Name -eq $PolicyName })

        if ($PolicyExists) {
            $SetParams = ConvertTo-CIPPComplianceSetParams -Params $PolicyParams -Identity $PolicyName -AddPrefixFields $LocationFields
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-RetentionCompliancePolicy' -cmdParams $SetParams -Compliance -AsApp -useSystemMailbox $true
            $PolicyAction = "Updated retention compliance policy '$PolicyName' in $TenantFilter."
        } else {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-RetentionCompliancePolicy' -cmdParams $PolicyParams -Compliance -AsApp -useSystemMailbox $true
            $PolicyAction = "Created retention compliance policy '$PolicyName' in $TenantFilter."
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

            $RuleExists = [bool]($ExistingRules | Where-Object { $_.Name -eq $RuleName -or $_.Policy -eq $PolicyName })

            if ($RuleExists) {
                $SetRuleHash = ConvertTo-CIPPComplianceSetParams -Params $RuleHash -Identity $RuleName
                $SetRuleHash.Remove('Policy') | Out-Null
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-RetentionComplianceRule' -cmdParams $SetRuleHash -Compliance -AsApp -useSystemMailbox $true
            } else {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-RetentionComplianceRule' -cmdParams $RuleHash -Compliance -AsApp -useSystemMailbox $true
            }
        }

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $PolicyAction -sev Info
        return $PolicyAction
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $msg = "Could not deploy retention compliance policy '$PolicyName' to $($TenantFilter): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Error -LogData $ErrorMessage
        return $msg
    }
}
