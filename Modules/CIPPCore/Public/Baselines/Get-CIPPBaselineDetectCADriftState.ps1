function Get-CIPPBaselineDetectCADriftState {
    <#
    .SYNOPSIS
        Prepare hook for the DetectConditionalAccessDrift standard: flags admin-created CA policies.
    .DESCRIPTION
        Builds the MANAGED set - the display names of every Conditional Access template
        any baseline applies to this tenant (across ALL baselines) - and compares it
        against the tenant's live CA policy cache. Every live policy whose display name
        matches no managed template is drift: one label-keyed diff per policy, so
        operators accept or deny-delete each rogue policy individually through per-path
        triage. Matching is by display name, case-insensitive, after tenant-token
        replacement. Report-only by design: no remediate executor.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $ManagedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    # The template store is read ONCE and indexed under every key a config may reference:
    # RowKey, the GUID column, and the payload displayName - the legacy reference form that
    # both the CA prepare and the CATemplate executor still honour. Resolving fewer keys here
    # than the deploy path does would leave a policy a baseline actively manages outside the
    # managed set, flag it as unmanaged, and let a deny-delete verdict delete it out from
    # under that baseline on the next run.
    $TemplatesTable = Get-CippTable -tablename 'templates'
    $TemplateNames = @{}
    foreach ($TemplateRow in @(try { Get-CIPPAzDataTableEntity @TemplatesTable -Filter "PartitionKey eq 'CATemplate'" } catch { @() })) {
        $TemplateName = "$(try { ($TemplateRow.JSON | ConvertFrom-Json -Depth 100).displayName } catch { $null })"
        if (-not $TemplateName) { continue }
        foreach ($Key in @("$($TemplateRow.RowKey)", "$($TemplateRow.GUID)", $TemplateName)) {
            if ($Key -and -not $TemplateNames.ContainsKey($Key)) { $TemplateNames[$Key] = $TemplateName }
        }
    }
    $WorkItems = @(try { Get-CIPPBaselineWorkItems -TenantFilter $TenantFilter } catch { @() })
    $Unwrap = { param($Value) if ($Value -is [System.Management.Automation.PSCustomObject] -and $null -ne $Value.value) { $Value.value } else { $Value } }
    foreach ($WorkItem in ($WorkItems | Where-Object { $_.BaseName -eq 'ConditionalAccessTemplate' })) {
        $TemplateRef = "$(& $Unwrap $WorkItem.Variables.caTemplate)"
        if (-not $TemplateRef) { continue }
        $TemplateName = $TemplateNames[$TemplateRef]
        if (-not $TemplateName) { continue }
        $Resolved = $(try { Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $TemplateName } catch { $TemplateName })
        $null = $ManagedNames.Add("$Resolved")
    }

    $CacheMeta = $(try { Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'ConditionalAccessPolicies' -CountsOnly } catch { $null })
    if ($null -eq $CacheMeta) {
        # Never collected: the engine's collector-on-miss / No Data semantics take over.
        return @{ Expected = [PSCustomObject]@{}; Current = $null }
    }

    $Expected = [PSCustomObject]@{}
    $Current = [PSCustomObject]@{}
    $Policies = @($(try { New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ConditionalAccessPolicies' } catch { $null }) | Where-Object { $_ })
    foreach ($Policy in $Policies) {
        $PolicyName = "$($Policy.displayName)"
        if (-not $PolicyName) { continue }
        if ($ManagedNames.Contains($PolicyName)) { continue }
        $Expected | Add-Member -NotePropertyName $PolicyName -NotePropertyValue $null -Force
        $Current | Add-Member -NotePropertyName $PolicyName -NotePropertyValue ([PSCustomObject]@{
                state  = "$($Policy.state)"
                id     = "$($Policy.id)"
                status = 'Not covered by any baseline template'
            }) -Force
    }

    return @{ Expected = $Expected; Current = $Current }
}
