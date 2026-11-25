function Get-CIPPManagedBaselineRequestBody {
    <#
    .SYNOPSIS
        Builds exactly what a custom managed baseline request sends to CyberDrain.
    .DESCRIPTION
        What was typed on the request form plus the stored, already redacted compare result of
        every standard. Used both to send the request and to show the partner what was sent,
        so the two can never differ. Carries no tenant id, domain or name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Row)

    $Table = Get-CippTable -tablename 'ManagedBaselineCollection'
    $SafeId = ConvertTo-CIPPODataFilterValue -Value $Row.RowKey
    $Standards = foreach ($Entry in (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeId'" | Sort-Object -Property RowKey)) {
        $Current = $null
        if ($Entry.Current) {
            try { $Current = ConvertFrom-Json -InputObject "$($Entry.Current)" -Depth 100 -NoEnumerate -ErrorAction Stop } catch { $Current = $null }
        }
        $DiffersOn = @()
        if ($Entry.DiffersOn) {
            try { $DiffersOn = @(ConvertFrom-Json -InputObject "$($Entry.DiffersOn)" -ErrorAction Stop) } catch { $DiffersOn = @() }
        }
        [ordered]@{
            standard   = "$($Entry.RowKey)"
            status     = "$($Entry.Status)"
            inBaseline = [bool]$Entry.InBaseline
            current    = $Current
            differsOn  = $DiffersOn
        }
    }

    $Frameworks = @()
    if ($Row.Frameworks) {
        try { $Frameworks = @(ConvertFrom-Json -InputObject "$($Row.Frameworks)" -ErrorAction Stop) } catch { $Frameworks = @() }
    }

    [ordered]@{
        requestId   = "$($Row.RowKey)"
        cippVersion = "$($env:APP_VERSION)"
        industry    = "$($Row.Industry)"
        clientSize  = "$($Row.ClientSize)"
        wants       = "$($Row.Wants)"
        exceptions  = "$($Row.Exceptions)"
        frameworks  = $Frameworks
        comments    = "$($Row.Comments)"
        collectedAt = [int64]($Row.CollectedAt ?? 0)
        standards   = @($Standards)
    }
}
