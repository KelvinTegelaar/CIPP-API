function Get-GraphBulkResultByID ($Results, $ID, [switch]$Value) {
    <#
    .FUNCTIONALITY
    Internal
    #>
    if ($Value) {
    ($Results | Where-Object { $_.id -eq $ID }).body.value
    } else {
        ($Results | Where-Object { $_.id -eq $ID }).body
    }
}
