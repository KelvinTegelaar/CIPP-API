function Expand-CIPPBaselineTemplatePackage {
    <#
    .SYNOPSIS
        Expands a template-package standard instance into one member config per tagged template.
    .DESCRIPTION
        Packages are V2's tag system carried forward unchanged: the single free-text
        `Package` column on the templates table, grouped by name (the name IS the key -
        there is no package registry). A package standard stores only the package NAME;
        membership is resolved fresh on every call (late binding - the whole point:
        adding a template to the package adds it to every baseline referencing the
        package, without touching the baseline).

        One package instance in -> N member configs out, each shaped exactly like a
        hand-added standardsConfig entry for the member standard (IntuneTemplate /
        ConditionalAccessTemplate), so everything downstream - engine, prepare, identity
        based conflict detection, detect-drift managed sets, labels - treats them
        identically to manually configured instances. Deploy options and the action
        posture are copied verbatim onto every member (V2 semantics: uniform settings
        across a package; per-member overrides are what hand-added instances are for).

        Member instance keys are DERIVED and STABLE: '<Member>#p<pkgInstanceId>-<8 chars
        of the template ref>'. Stability matters because resolved rows, history
        partitions, triage verdicts and tenant overrides all key on the instance key -
        membership changes must never migrate another member's state. A template removed
        from the package stops resolving and the scheduled reconciliation clears its
        rows; an empty or deleted package expands to zero members (never an error).

        Driven by the definition's declarative `package` block:
          { "memberStandard": "IntuneTemplate", "memberVariable": "intuneTemplate",
            "variable": "intuneTemplatePackage", "templatePartition": "IntuneTemplate" }
        No name-based fallbacks: a definition without a package block is not expandable.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Definition,
        $Config,
        # Optional pre-fetched rows of the template partition, so callers iterating many
        # tenants query the templates table once instead of once per tenant.
        $TemplateRows
    )

    if (-not $Definition.package) { return @() }
    $Variables = $Config.variables
    if ($Variables -is [System.Collections.IDictionary]) { $Variables = [PSCustomObject]$Variables }
    $PackageRaw = $Variables.$($Definition.package.variable)
    if ($PackageRaw -is [System.Management.Automation.PSCustomObject] -and $null -ne $PackageRaw.value) { $PackageRaw = $PackageRaw.value }
    $PackageName = "$PackageRaw"
    if (-not $PackageName) { return @() }

    if ($null -eq $TemplateRows) {
        $TemplatesTable = Get-CippTable -tablename 'templates'
        $SafePartition = ConvertTo-CIPPODataFilterValue -Value "$($Definition.package.templatePartition)"
        $TemplateRows = @(Get-CIPPAzDataTableEntity @TemplatesTable -Filter "PartitionKey eq '$SafePartition'")
    }

    $InstanceSuffix = if ("$($Config.instance)" -match '#(.+)$') { $Matches[1] } else { 'pkg' }
    # Sorted for deterministic expansion order; -eq on strings is case-insensitive,
    # matching how the tag pickers group the column.
    $Members = foreach ($TemplateRow in ($TemplateRows | Where-Object { "$($_.Package)" -eq $PackageName } | Sort-Object -Property RowKey)) {
        $TemplateRef = if ("$($TemplateRow.GUID)") { "$($TemplateRow.GUID)" } else { "$($TemplateRow.RowKey)" }
        $KeyPart = ($TemplateRef -replace '[^a-zA-Z0-9]', '')
        if ($KeyPart.Length -gt 8) { $KeyPart = $KeyPart.Substring(0, 8) }
        $MemberVariables = [PSCustomObject]@{}
        foreach ($Property in $Variables.PSObject.Properties) {
            if ($Property.Name -eq "$($Definition.package.variable)") { continue }
            $MemberVariables | Add-Member -NotePropertyName $Property.Name -NotePropertyValue $Property.Value
        }
        $MemberVariables | Add-Member -NotePropertyName "$($Definition.package.memberVariable)" -NotePropertyValue $TemplateRef -Force
        [PSCustomObject]@{
            standard         = "$($Definition.package.memberStandard)"
            instance         = ('{0}#p{1}-{2}' -f $Definition.package.memberStandard, $InstanceSuffix, $KeyPart)
            variables        = $MemberVariables
            remediateEnabled = [bool]$Config.remediateEnabled
            alertEnabled     = [bool]$Config.alertEnabled
            alertOnRemediate = [bool]$Config.alertOnRemediate
            fromPackage      = $PackageName
        }
    }
    @($Members)
}
