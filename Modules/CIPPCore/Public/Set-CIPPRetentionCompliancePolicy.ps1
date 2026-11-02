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
    # Stored templates carry the policy comment as 'comments'.
    if (-not $PolicyParams.ContainsKey('Comment') -and -not [string]::IsNullOrWhiteSpace([string]$Template.comments)) {
        $PolicyParams['Comment'] = [string]$Template.comments
    }
    $RuleSource = $Template.RuleParams
    $PolicyName = $PolicyParams.Name
    $ErrorData = $null

    $ExistingPolicies = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionCompliancePolicy' -Compliance -AsApp | Select-Object Name, Guid } catch { @() }
    $ExistingRules = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionComplianceRule' -Compliance -AsApp | Select-Object Name, Policy } catch { @() }
    $ExistingPolicy = @($ExistingPolicies).Where({ $_.Name -eq $PolicyName }, 'First')[0]

    try {
        if ($ExistingPolicy) {
            $SetParams = ConvertTo-CIPPComplianceSetParams -Params $PolicyParams -Identity $PolicyName -AddPrefixFields $LocationFields
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-RetentionCompliancePolicy' -cmdParams $SetParams -Compliance -AsApp -useSystemMailbox $true
            $PolicyResult = "Updated retention compliance policy '$PolicyName' in $TenantFilter."
        } else {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-RetentionCompliancePolicy' -cmdParams $PolicyParams -Compliance -AsApp -useSystemMailbox $true
            $PolicyResult = "Created retention compliance policy '$PolicyName' in $TenantFilter."
        }
    } catch {
        $ErrorData = Get-CippException -Exception $_
        $PolicyResult = "Could not $(if ($ExistingPolicy) { 'update' } else { 'create' }) retention compliance policy '$PolicyName' in $($TenantFilter): $($ErrorData.NormalizedError)"
    }

    # A refused update must not stop an existing rule-less policy from getting its rule.
    if ($RuleSource -and ($ExistingPolicy -or -not $ErrorData)) {
        $RuleHash = Format-CIPPCompliancePolicyParams -Source $RuleSource -AllowedFields $RuleAllowedFields
        $RuleHash['Policy'] = $PolicyName
        $RuleName = if ($RuleHash.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace([string]$RuleHash['Name'])) {
            $RuleHash['Name']
        } else {
            "$PolicyName Rule"
        }
        $RuleHash['Name'] = $RuleName

        # A policy holds at most one rule, and the rule names its policy by GUID.
        $ExistingRule = if ($ExistingPolicy) { @($ExistingRules).Where({ $_.Policy -eq $ExistingPolicy.Guid }, 'First')[0] }

        try {
            if ($ExistingRule) {
                $SetRuleHash = ConvertTo-CIPPComplianceSetParams -Params $RuleHash -Identity $ExistingRule.Name
                $SetRuleHash.Remove('Policy') | Out-Null
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-RetentionComplianceRule' -cmdParams $SetRuleHash -Compliance -AsApp -useSystemMailbox $true
                $RuleResult = "Updated rule '$($ExistingRule.Name)'."
            } else {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-RetentionComplianceRule' -cmdParams $RuleHash -Compliance -AsApp -useSystemMailbox $true
                $RuleResult = "Created rule '$RuleName'."
            }
        } catch {
            $ErrorData = Get-CippException -Exception $_
            $RuleResult = "Could not deploy its retention rule '$RuleName': $($ErrorData.NormalizedError)"
        }
    }

    $Result = "$PolicyResult $RuleResult".Trim()
    if ($ErrorData) {
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorData
        throw $Result
    }
    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
    return $Result
}
