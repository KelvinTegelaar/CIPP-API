function Compare-CIPPGSAFilteringProfile {
    <#
    .SYNOPSIS
        Compares a Global Secure Access security profile template, and the filtering policy
        templates it links, with a tenant's filtering profiles and policies.
    .DESCRIPTION
        Reads nothing: TenantRows are NetworkAccessFiltering cache rows or a live read in the same
        shape, and WebCategories is the tenant's connectivity/webCategories list (omit to skip that
        check). Returns one finding per profile, policy, invalid category and link, each with a
        state of match, missing, drift or conflict and the id of the tenant object it matched.
        A conflict is something a deploy must refuse; missing and drift are what a deploy fixes.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ProfileTemplate,
        [hashtable]$PolicyTemplates = @{},
        [object[]]$TenantRows = @(),
        [object[]]$WebCategories
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $Profiles = $TenantRows.Where({ $_.kind -eq 'profile' })
    $PoliciesByName = @{}
    foreach ($Row in $TenantRows.Where({ $_.kind -eq 'policy' })) { $PoliciesByName[[string]$Row.name] = $Row }
    $ValidCategories = if ($null -ne $WebCategories) { [System.Collections.Generic.HashSet[string]]::new([string[]]@($WebCategories.name), [System.StringComparer]::OrdinalIgnoreCase) }

    $Named = @($Profiles.Where({ $_.name -eq $ProfileTemplate.name }))
    $Holder = $Profiles.Where({ [int64]$_.priority -eq [int64]$ProfileTemplate.priority -and $_.name -ne $ProfileTemplate.name }, 'First')
    $TenantProfile = if ($Named.Count -eq 1) { $Named[0] }
    $State, $Detail = if ($Named.Count -gt 1) {
        'conflict', "$($Named.Count) profiles are named '$($ProfileTemplate.name)', so CIPP cannot tell which one to manage"
    } elseif ($Holder.Count) {
        'conflict', "priority $($ProfileTemplate.priority) is already used by profile '$($Holder[0].name)'"
    } elseif (-not $TenantProfile) {
        'missing', 'not in the tenant'
    } else {
        $Diff = @(
            if ($TenantProfile.state -ne $ProfileTemplate.state) { "state is $($TenantProfile.state), expected $($ProfileTemplate.state)" }
            if ([int64]$TenantProfile.priority -ne [int64]$ProfileTemplate.priority) { "priority is $($TenantProfile.priority), expected $($ProfileTemplate.priority)" }
            if ([string]$TenantProfile.description -ne [string]$ProfileTemplate.description) { 'description differs' }
        )
        if ($Diff.Count) { 'drift', ($Diff -join '; ') } else { 'match', $null }
    }
    $Findings.Add([pscustomobject]@{ object = 'profile'; name = $ProfileTemplate.name; state = $State; detail = $Detail; id = $TenantProfile.id })

    $TemplatePolicyNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Link in @($ProfileTemplate.policies)) {
        $PolicyTemplate = $PolicyTemplates[[string]$Link.policy.value]
        if (-not $PolicyTemplate) {
            $null = $TemplatePolicyNames.Add([string]$Link.policy.label)
            $Findings.Add([pscustomobject]@{ object = 'policy'; name = $Link.policy.label; state = 'conflict'; detail = "the linked filtering policy template ($($Link.policy.value)) no longer exists"; id = $null })
            continue
        }
        $null = $TemplatePolicyNames.Add($PolicyTemplate.name)

        $TemplateRules = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Rule in @($PolicyTemplate.policyRules)) {
            $null = $TemplateRules.Add("$($Rule.ruleType): " + ((@($Rule.destinations).ForEach({ $_.name ?? $_.value }) | Sort-Object) -join ', '))
            if ($ValidCategories -and $Rule.ruleType -eq 'webCategory') {
                foreach ($Category in @($Rule.destinations).Where({ -not $ValidCategories.Contains([string]$_.name) })) {
                    $Findings.Add([pscustomobject]@{ object = 'category'; name = $Category.name; state = 'conflict'; detail = "not a web category this tenant offers (policy '$($PolicyTemplate.name)')"; id = $null })
                }
            }
        }

        $TenantPolicy = $PoliciesByName[[string]$PolicyTemplate.name]
        $State, $Detail = if (-not $TenantPolicy) {
            'missing', 'not in the tenant'
        } else {
            $TenantRules = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Rule in @($TenantPolicy.policyRules)) { $null = $TenantRules.Add("$($Rule.ruleType): " + ((@($Rule.destinations).ForEach({ $_.name ?? $_.value }) | Sort-Object) -join ', ')) }
            $Diff = @(
                if ($TenantPolicy.action -ne $PolicyTemplate.action) { "action is $($TenantPolicy.action), expected $($PolicyTemplate.action)" }
                if ([string]$TenantPolicy.description -ne [string]$PolicyTemplate.description) { 'description differs' }
                foreach ($Key in $TemplateRules) { if (-not $TenantRules.Contains($Key)) { "rule missing: $Key" } }
                foreach ($Key in $TenantRules) { if (-not $TemplateRules.Contains($Key)) { "rule not in the template: $Key" } }
            )
            if ($Diff.Count) { 'drift', ($Diff -join '; ') } else { 'match', $null }
        }
        $Findings.Add([pscustomobject]@{ object = 'policy'; name = $PolicyTemplate.name; state = $State; detail = $Detail; id = $TenantPolicy.id })

        $TenantLink = if ($TenantProfile) { @($TenantProfile.policies).Where({ $_.policy.name -eq $PolicyTemplate.name }, 'First')[0] }
        $State, $Detail = if (-not $TenantLink) {
            'missing', 'not linked in the tenant'
        } else {
            $Diff = @(
                if ([int64]$TenantLink.priority -ne [int64]$Link.priority) { "priority is $($TenantLink.priority), expected $($Link.priority)" }
                if ($TenantLink.state -ne $Link.state) { "state is $($TenantLink.state), expected $($Link.state)" }
                if ($Link.loggingState -and $TenantLink.loggingState -ne $Link.loggingState) { "logging is $($TenantLink.loggingState), expected $($Link.loggingState)" }
            )
            if ($Diff.Count) { 'drift', ($Diff -join '; ') } else { 'match', $null }
        }
        $Findings.Add([pscustomobject]@{ object = 'link'; name = "$($ProfileTemplate.name) -> $($PolicyTemplate.name)"; state = $State; detail = $Detail; id = $TenantLink.id })
    }

    if ($TenantProfile) {
        foreach ($Extra in @($TenantProfile.policies).Where({ -not $TemplatePolicyNames.Contains([string]$_.policy.name) })) {
            $Findings.Add([pscustomobject]@{ object = 'link'; name = "$($ProfileTemplate.name) -> $($Extra.policy.name)"; state = 'drift'; detail = 'linked in the tenant but not in the template'; id = $Extra.id })
        }
    }

    $Findings
}
