function Get-CippBulkStatusCode {
    <#
    .SYNOPSIS
        Status code for a request that acts on several items: 200 all succeeded, 207 some failed, 500 all failed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Total,
        [Parameter(Mandatory)][int]$Failed
    )
    if ($Failed -le 0) { return [System.Net.HttpStatusCode]::OK }
    if ($Failed -ge $Total) { return [System.Net.HttpStatusCode]::InternalServerError }
    [System.Net.HttpStatusCode]::MultiStatus
}
