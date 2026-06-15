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

        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$fixedObject"
            RowKey       = "$($Template.GUID)"
            GUID         = "$($Template.GUID)"
            PartitionKey = 'IntuneTemplate'
        } -Force

        $Template.RAWJson = $currentRawJson
        Write-LogMessage -API 'IntuneTemplate' -message "Repaired double-nested RAWJson for template '$($Template.Displayname)' ($($Template.GUID))" -Sev 'Warning'
    }

    return $Template
}
