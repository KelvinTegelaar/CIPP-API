function New-CIPPBecCaseId {
    <#
    .SYNOPSIS
        Mints a new BEC case id.
    .DESCRIPTION
        Case ids are BEC-<yyyyMMddHHmmss>-<6 hex>: the timestamp prefix keeps them chronologically
        sortable as table RowKeys (so a user's run history lists in order) and the random suffix keeps
        two runs queued in the same second distinct. The id is stamped on the run row, the results
        row, every logbook entry written during the case and the evidence package.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    return 'BEC-{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'), [guid]::NewGuid().ToString('N').Substring(0, 6)
}
