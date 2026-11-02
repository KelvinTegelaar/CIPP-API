function Get-CIPPBaselineSensitiveInfoTypeTemplateState {
    <#
    .SYNOPSIS
        Prepare hook for SensitiveInfoTypeTemplate: this instance's SIT sync state against
        the live rule pack.
    .DESCRIPTION
        One instance grades ONE template - the baseline stores an instance per selected
        template (instanceIdentity), so the hook resolves a single reference.

        The only one of the template families that diffs rather than checking presence, and
        it reads LIVE rather than from a cache. Compare-CIPPSensitiveInfoType needs the
        SIT's rule package XML, which is a second per-SIT call
        (Get-DlpSensitiveInformationTypeRulePackage keyed on the SIT's RulePackId) that no
        cache carries. Grading off the SIT list alone would only ever detect a missing SIT,
        never a drifted one - which is the whole point of this standard.

        The compare returns one of five states. Missing, Drift and Invalid are
        non-compliant, exactly as the classic graded them. InSync is compliant, and so is
        BuiltIn: a Microsoft SIT cannot be modified, so a template that collides with one is
        left alone rather than reported as a failure forever.

        Only Missing and Drift are remediable. Invalid means the TEMPLATE is broken -
        neither Pattern nor FileDataBase64 - so deploying it would fail; it is reported and
        left, and remediableTemplates stays empty.

        Template resolution is written out here rather than shared: PartitionKey
        'SensitiveInfoTypeTemplate', RowKey alone.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Reference = $Item.Variables.sensitiveInfoTypeTemplate
    if ($Reference -is [System.Management.Automation.PSCustomObject] -and $Reference.PSObject.Properties.Name -contains 'value') { $Reference = $Reference.value }
    if ([string]::IsNullOrWhiteSpace("$Reference")) { return @{ Current = $null } }

    $Table = Get-CippTable -tablename 'templates'
    $SafeReference = ConvertTo-CIPPODataFilterValue -Value "$Reference"
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'SensitiveInfoTypeTemplate' and RowKey eq '$SafeReference'" | Select-Object -First 1
    $Template = $(if ($Entity -and -not [string]::IsNullOrWhiteSpace($Entity.JSON)) { try { $Entity.JSON | ConvertFrom-Json -Depth 20 -ErrorAction Stop } catch { $null } })
    if (-not $Template) { return @{ Current = $null } }

    # A failed compare is NOT drift - the tenant read failed, and reporting the SIT as
    # broken would be a lie that remediation would then act on.
    $Comparison = try {
        Compare-CIPPSensitiveInfoType -TenantFilter $TenantFilter -Template $Template -ErrorAction Stop
    } catch {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Could not compare Sensitive Information Type '$($Template.Name)': $($_.Exception.Message)" -Sev 'Error'
        return @{ Current = $null }
    }
    if (-not $Comparison) { return @{ Current = $null } }

    $NonCompliant = @(if ("$($Comparison.State)" -in @('Missing', 'Drift', 'Invalid')) { $Comparison })
    $Remediable = @(if ("$($Comparison.State)" -in @('Missing', 'Drift')) { $Template })

    $Current = [PSCustomObject]@{ nonCompliantSensitiveInfoTypes = @($NonCompliant) }
    # Carried for the executor, not graded.
    $Current | Add-Member -NotePropertyName 'remediableTemplates' -NotePropertyValue @($Remediable)

    @{
        Expected = [PSCustomObject]@{ nonCompliantSensitiveInfoTypes = @() }
        Current  = $Current
    }
}
