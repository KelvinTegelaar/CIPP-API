function Get-CIPPBaselineSensitivityLabelTemplateState {
    <#
    .SYNOPSIS
        Prepare hook for SensitivityLabelTemplate: is this instance's label deployed.
    .DESCRIPTION
        One instance grades ONE template - the baseline stores an instance per selected
        template (instanceIdentity), so the hook resolves a single reference rather than a
        selection list.

        Grades PRESENCE BY NAME only, which is what the classic standard graded. A label
        carries far more than its name - encryption, marking, scope - but the classic never
        diffed any of it, and the deploy path overwrites those settings wholesale on every
        run, so grading them would report drift the engine would then 'fix' by overwriting
        operator changes it was never asked to manage.

        The template name matches an existing label on EITHER Name or DisplayName. Purview
        returns the two independently and a label created outside CIPP routinely has a
        GUID-ish Name with the human name only in DisplayName, so matching one alone reports
        a deployed label as missing and redeploys it.

        Template resolution is written out here rather than shared. This family looks up
        PartitionKey 'SensitivityLabelTemplate' by RowKey alone and reads the label name
        from the payload's Name. Other template families use different partitions and
        different name fields; borrowing one would silently resolve the wrong rows.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Labels = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoLabels')
    if ($Labels.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoLabels')) {
        return @{ Current = $null }
    }

    # The picker stores either a plain id or a { label, value } object depending on how the
    # baseline was saved.
    $Reference = $Item.Variables.sensitivityLabelTemplate
    if ($Reference -is [System.Management.Automation.PSCustomObject] -and $Reference.PSObject.Properties.Name -contains 'value') { $Reference = $Reference.value }
    if ([string]::IsNullOrWhiteSpace("$Reference")) { return @{ Current = $null } }

    $Table = Get-CippTable -tablename 'templates'
    $SafeReference = ConvertTo-CIPPODataFilterValue -Value "$Reference"
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'SensitivityLabelTemplate' and RowKey eq '$SafeReference'" | Select-Object -First 1
    $Template = $(if ($Entity -and -not [string]::IsNullOrWhiteSpace($Entity.JSON)) { try { $Entity.JSON | ConvertFrom-Json -Depth 20 -ErrorAction Stop } catch { $null } })
    # A deleted or unreadable template is not a compliant tenant - the standard cannot
    # evaluate, so it reports No Data rather than an empty success.
    $TemplateName = "$($Template.Name)"
    if (-not $Template -or [string]::IsNullOrWhiteSpace($TemplateName)) { return @{ Current = $null } }

    $Deployed = [bool]($Labels | Where-Object { "$($_.Name)" -eq $TemplateName -or "$($_.DisplayName)" -eq $TemplateName })

    $Current = [PSCustomObject]@{ missingLabels = @(if (-not $Deployed) { $TemplateName }) }
    # Carried for the executor, not graded.
    $Current | Add-Member -NotePropertyName 'templateBodies' -NotePropertyValue @($Template)

    @{
        Expected = [PSCustomObject]@{ missingLabels = @() }
        Current  = $Current
    }
}
