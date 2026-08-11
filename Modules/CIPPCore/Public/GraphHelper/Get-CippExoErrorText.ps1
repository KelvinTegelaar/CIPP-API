function Get-CippExoErrorText {
    <#
    .SYNOPSIS
    Pulls a readable message out of an Exchange bulk error record.

    .DESCRIPTION
    New-ExoBulkRequest sets 'error' to error.details.message when Exchange supplies one and falls
    back to error.message otherwise, so the value is normally a string - but callers also hand this
    raw Graph-style objects, so handle both rather than printing a type name at the operator.
    #>
    [CmdletBinding()]
    param($ErrorRecord)

    $ErrorValue = $ErrorRecord.error ?? $ErrorRecord
    if ($ErrorValue -is [string]) { return $ErrorValue }
    if ($ErrorValue.details.message) { return [string]$ErrorValue.details.message }
    if ($ErrorValue.message) { return [string]$ErrorValue.message }
    return [string]$ErrorValue
}