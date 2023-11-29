function Get-GraphBulkResultByID ($Results, $ID, [switch]$Value) {
    if ($Value) {
    ($Results | Where-Object { $_.id -eq $ID }).body.value
    } else {
        ($Results | Where-Object { $_.id -eq $ID }).body
    }
}
