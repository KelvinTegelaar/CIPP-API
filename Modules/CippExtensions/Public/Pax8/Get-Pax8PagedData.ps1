function Get-Pax8PagedData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [hashtable]$Query = @{},
        [int]$PageSize = 200
    )

    $Page = 0
    $Results = [System.Collections.Generic.List[object]]::new()
    do {
        $PageQuery = @{}
        foreach ($Item in $Query.GetEnumerator()) {
            $PageQuery[$Item.Key] = $Item.Value
        }
        $PageQuery.page = $Page
        $PageQuery.size = $PageSize
        $Response = Invoke-Pax8Request -Method GET -Path $Path -Query $PageQuery

        $Items = if ($Response.content) {
            @($Response.content)
        } elseif ($Response.items) {
            @($Response.items)
        } elseif ($Response.data) {
            @($Response.data)
        } elseif ($Response -is [array]) {
            @($Response)
        } else {
            @()
        }
        foreach ($Item in $Items) {
            $Results.Add($Item)
        }

        $TotalPages = if ($Response.page.totalPages) {
            [int]$Response.page.totalPages
        } elseif ($Response.totalPages) {
            [int]$Response.totalPages
        } else {
            1
        }
        $Page++
    } while ($Page -lt $TotalPages)

    return @($Results)
}
