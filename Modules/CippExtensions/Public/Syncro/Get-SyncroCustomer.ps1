function Get-SyncroCustomer {
    <#
    .SYNOPSIS
        Lists every active customer in the configured Syncro instance.
    .DESCRIPTION
        GET /customers answers 25 (or, on some instances, 100) customers per page with a meta
        block carrying total_pages, so the pages are walked until that count is reached.
        Disabled customers are left out: a ticket raised against one would never be worked.
    .PARAMETER Configuration
        The Syncro block of the extension configuration.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Configuration
    )

    $Customers = [System.Collections.Generic.List[object]]::new()
    $Page = 1
    do {
        $Result = Invoke-SyncroRequest -Configuration $Configuration -Endpoint '/customers' -Query @{ page = $Page }
        foreach ($Customer in @($Result.customers)) {
            if ($null -ne $Customer) { $Customers.Add($Customer) }
        }
        $TotalPages = [int]($Result.meta.total_pages ?? 1)
        $Page++
    } while ($Page -le $TotalPages)

    return $Customers
}
