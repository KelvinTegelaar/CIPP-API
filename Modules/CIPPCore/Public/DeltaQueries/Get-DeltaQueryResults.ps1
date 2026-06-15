function Get-DeltaQueryResults {
    <#
    .SYNOPSIS
        Retrieves results for Delta Queries
    .DESCRIPTION
        This helper function modifies the results from Delta Query triggers based on specified properties.
    .PARAMETER Data
        The data containing Delta Query results. Use %triggerdata% from the scheduler to pass in the data.
    .PARAMETER Properties
        A comma-separated list of properties to include in the output. If not specified, all properties are returned.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        [string]$Properties,
        [string]$TenantFilter,
        $Headers
    )

    $Properties = $Properties -split ',' | ForEach-Object { $_.Trim() }
    if (!$Properties -or $Properties.Count -eq 0) {
        Write-Information 'No specific properties requested, returning all data.'
        Write-Information ($Data | ConvertTo-Json -Depth 10)
        return $Data
    }

    $Data = $Data | Select-Object -Property $Properties
}
