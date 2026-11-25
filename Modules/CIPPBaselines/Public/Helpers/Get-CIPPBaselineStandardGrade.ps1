function Get-CIPPBaselineStandardGrade {
    <#
    .SYNOPSIS
        Compares one standard against one tenant without writing anything, and says how it went.
    .DESCRIPTION
        Runs the engine in compare-only mode, so alignment and history are untouched. With no
        variables the standard is graded against CIPP's own default settings; a blank variable
        takes its default either way. Returns Status ('Compliant', 'Drift', 'No licence',
        'No Data' or 'Needs a choice'), CurrentValue, Diff and the Definition. A standard that
        needs a template, or a value only a person can choose, and did not get one is
        'Needs a choice' and nothing is read from the tenant.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$Standard,
        $Variables,
        [string]$SourceTemplate = 'Managed baseline snapshot'
    )

    $Definition = Get-CIPPBaselineDefinition -Name $Standard | Select-Object -First 1
    if (-not $Definition) { throw "No definition found for standard $Standard." }

    if ($Variables -is [System.Collections.IDictionary]) { $Variables = [PSCustomObject]$Variables }
    if ($null -ne $Variables -and @($Variables.PSObject.Properties).Count -eq 0) { $Variables = $null }
    $Supplied = {
        param($Name)
        $null -ne $Variables -and $Variables.PSObject.Properties[$Name] -and "$($Variables.$Name.value ?? $Variables.$Name)" -ne ''
    }

    # The engine's own rule for a setting it cannot fill in: no default, and either required
    # or still present in the expected value.
    $ExpectedJson = ''
    if ($null -ne $Definition.expected) { $ExpectedJson = ConvertTo-Json -Compress -Depth 100 -InputObject $Definition.expected }
    $NeedsChoice = [bool]$Definition.instanceIdentity -and -not (& $Supplied "$($Definition.instanceIdentity)")
    if (-not $NeedsChoice) {
        foreach ($Variable in (($Definition.variables ?? [PSCustomObject]@{}).PSObject.Properties)) {
            if ($null -ne ($Variable.Value.default ?? $Variable.Value.recommended)) { continue }
            if (& $Supplied $Variable.Name) { continue }
            if ($Variable.Value.required -eq $true -or ($Variable.Value.omitWhenBlank -ne $true -and $ExpectedJson.Contains(('%{0}%' -f $Variable.Name)))) {
                $NeedsChoice = $true
                break
            }
        }
    }

    $Grade = [PSCustomObject]@{ Status = 'No Data'; CurrentValue = $null; Diff = @(); Definition = $Definition }
    if ($NeedsChoice) {
        $Grade.Status = 'Needs a choice'
        return $Grade
    }

    $WorkItem = @{
        TenantFilter     = $TenantFilter
        TenantName       = $TenantFilter
        Standard         = $Standard
        BaseName         = $Standard
        Variables        = $Variables
        Tiers            = @()
        Stage            = 1
        StageName        = ''
        TemplateId       = ''
        SourceScope      = 'managed'
        SourceTemplate   = $SourceTemplate
        RemediateEnabled = $false
        AlertEnabled     = $false
    }
    $Graded = Invoke-CIPPBaselineStandard -Item $WorkItem -Mode 'compare' -GradeOnly
    if ($null -eq $Graded) { return $Grade }
    if ($Graded.PSObject.Properties['Outcome']) {
        # A full result means the engine stopped before grading and says why.
        if ("$($Graded.Status)" -eq 'Skipped - No License') { $Grade.Status = 'No licence' }
        return $Grade
    }
    if ($null -ne $Graded.CurrentValue) {
        $Grade.Status = $Graded.Compliant ? 'Compliant' : 'Drift'
        $Grade.CurrentValue = $Graded.CurrentValue
        $Grade.Diff = @($Graded.Diff)
    }
    $Grade
}
