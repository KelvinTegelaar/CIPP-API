function Invoke-CIPPBaselineSafeLinksTemplatePolicy {
    <#
    .SYNOPSIS
        SafeLinksTemplatePolicy executor: upserts the policy, its rule, and the rule state.
    .DESCRIPTION
        The classic's three-step write, ported whole: New-/Set-SafeLinksPolicy with the
        mapped policy fields, New-/Set-SafeLinksRule with the recipient scoping (the rule
        binds to the policy only on create - the binding cannot change on Set-), then
        Enable-/Disable-SafeLinksRule when the template expresses a state.

        Applied in full on every remediation run (checkBeforeRun:false): the compare only
        grades presence, and the rewrite is what repairs setting drift it cannot see.

        Array-ish template fields (SentTo, DoNotRewriteUrls, ...) normalize through the
        classic's unwrap rules - autoComplete pickers store {label,value} objects, user
        pickers store userPrincipalName, and a bare string is itself.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    function ConvertTo-CIPPBaselineSafeLinksArray {
        param($Field)
        if ($null -eq $Field) { return @() }
        $Result = [System.Collections.Generic.List[string]]::new()
        foreach ($FieldItem in @($Field)) {
            if ($null -eq $FieldItem) { continue }
            if ($FieldItem -is [string]) { $Result.Add($FieldItem); continue }
            if ($FieldItem.value) { $Result.Add("$($FieldItem.value)"); continue }
            if ($FieldItem.userPrincipalName) { $Result.Add("$($FieldItem.userPrincipalName)"); continue }
            if ($FieldItem.id) { $Result.Add("$($FieldItem.id)"); continue }
            $Result.Add("$FieldItem")
        }
        return $Result.ToArray()
    }

    $Template = $Current.templateBody
    $PolicyName = "$($Current.policyName)"
    $RuleName = "$($Current.ruleName)"
    if (-not $Template -or [string]::IsNullOrWhiteSpace($PolicyName)) { return }

    $PolicyParams = @{}
    foreach ($Field in @('EnableSafeLinksForEmail', 'EnableSafeLinksForTeams', 'EnableSafeLinksForOffice', 'TrackClicks',
            'AllowClickThrough', 'ScanUrls', 'EnableForInternalSenders', 'DeliverMessageAfterScan', 'DisableUrlRewrite',
            'AdminDisplayName', 'CustomNotificationText', 'EnableOrganizationBranding')) {
        if ($null -ne $Template.$Field) { $PolicyParams[$Field] = $Template.$Field }
    }
    $DoNotRewriteUrls = ConvertTo-CIPPBaselineSafeLinksArray -Field $Template.DoNotRewriteUrls
    if ($DoNotRewriteUrls.Count -gt 0) { $PolicyParams['DoNotRewriteUrls'] = $DoNotRewriteUrls }

    if ($Current.policyDeployed -eq $true) {
        $PolicyParams['Identity'] = $PolicyName
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-SafeLinksPolicy' -cmdParams $PolicyParams -useSystemMailbox $true
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Updated SafeLinks policy '$PolicyName'." -Sev 'Info'
    } else {
        $PolicyParams['Name'] = $PolicyName
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-SafeLinksPolicy' -cmdParams $PolicyParams -useSystemMailbox $true
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Created SafeLinks policy '$PolicyName'." -Sev 'Info'
    }

    $RuleParams = @{}
    if ($null -ne $Template.Priority) { $RuleParams['Priority'] = $Template.Priority }
    if ($null -ne $Template.Description) { $RuleParams['Comments'] = $Template.Description }
    if ($null -ne $Template.TemplateDescription) { $RuleParams['Comments'] = $Template.TemplateDescription }
    foreach ($Field in @('SentTo', 'SentToMemberOf', 'RecipientDomainIs', 'ExceptIfSentTo', 'ExceptIfSentToMemberOf', 'ExceptIfRecipientDomainIs')) {
        $Values = ConvertTo-CIPPBaselineSafeLinksArray -Field $Template.$Field
        if ($Values.Count -gt 0) { $RuleParams[$Field] = $Values }
    }

    if ($Current.ruleDeployed -eq $true) {
        $RuleParams['Identity'] = $RuleName
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-SafeLinksRule' -cmdParams $RuleParams -useSystemMailbox $true
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Updated SafeLinks rule '$RuleName'." -Sev 'Info'
    } else {
        $RuleParams['Name'] = $RuleName
        $RuleParams['SafeLinksPolicy'] = $PolicyName
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-SafeLinksRule' -cmdParams $RuleParams -useSystemMailbox $true
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Created SafeLinks rule '$RuleName'." -Sev 'Info'
    }

    # Rule state: only when the template expresses one, in any of the classic's spellings.
    $IsEnabled = switch ("$($Template.State)") {
        'Enabled' { $true }
        'Disabled' { $false }
        'True' { $true }
        'False' { $false }
        default { $null }
    }
    if ($null -ne $IsEnabled) {
        $Cmdlet = if ($IsEnabled) { 'Enable-SafeLinksRule' } else { 'Disable-SafeLinksRule' }
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet $Cmdlet -cmdParams @{ Identity = $RuleName } -useSystemMailbox $true
    }
}
