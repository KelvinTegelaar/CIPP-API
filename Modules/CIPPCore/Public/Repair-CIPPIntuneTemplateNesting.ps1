function Repair-CIPPIntuneTemplateNesting {
    <#
    .SYNOPSIS
        Detects and repairs double-nested RAWJson in Intune templates, then resaves to table storage.
    .DESCRIPTION
        A past bug caused the outer template wrapper object (Displayname, Description, RAWJson, Type, GUID)
        to be serialized as the RAWJson value instead of the actual policy JSON. This function unwraps
        any depth of nesting and resaves the corrected template so the fix is permanent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Template,
        $Table
    )

    $currentRawJson = $Template.RAWJson
    $unwrapped = $false

    # Walk down nested RAWJson layers until we reach the actual policy JSON
    while ($currentRawJson) {
        try {
            $parsed = $currentRawJson | ConvertFrom-Json -Depth 20 -ErrorAction Stop
        } catch {
            break
        }

        if ($parsed.PSObject.Properties.Name -contains 'RAWJson') {
            # Still wrapped in a template envelope — go one level deeper
            $currentRawJson = $parsed.RAWJson
            $unwrapped = $true
        } else {
            break
        }
    }

    if ($unwrapped) {
        Write-Information "Repairing double-nested RAWJson for template '$($Template.Displayname)' ($($Template.GUID))"

        # Repair the in-memory copy regardless, so the caller gets usable JSON even if the resave
        # below is skipped or fails.
        $Template.RAWJson = $currentRawJson

        if ([string]::IsNullOrWhiteSpace($Template.GUID)) {
            # Without a GUID there is no RowKey to write back to, and guessing one would create a
            # junk row. The in-memory repair above still lets this run succeed.
            Write-Warning "Cannot persist the RAWJson repair for template '$($Template.Displayname)' because it has no GUID."
            return $Template
        }

        if (-not $Table) {
            $Table = Get-CippTable -tablename 'templates'
        }

        $fixedObject = [PSCustomObject]@{
            Displayname = $Template.Displayname
            Description = $Template.Description
            RAWJson     = $currentRawJson
            Type        = $Template.Type
            GUID        = $Template.GUID
        } | ConvertTo-Json -Depth 10 -Compress

        # Merge rather than replace. Package membership lives in its own column on the entity, not
        # in the JSON blob, and standards resolve a package by filtering on it. A replace drops
        # every column not listed here, which silently removes the template from its package - the
        # standard then stops running for it and its last compliance result is frozen for good.
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$fixedObject"
            RowKey       = "$($Template.GUID)"
            GUID         = "$($Template.GUID)"
            PartitionKey = 'IntuneTemplate'
        } -OperationType UpsertMerge

        Write-LogMessage -API 'IntuneTemplate' -message "Repaired double-nested RAWJson for template '$($Template.Displayname)' ($($Template.GUID))" -Sev 'Warning'
    }

    return $Template
}
