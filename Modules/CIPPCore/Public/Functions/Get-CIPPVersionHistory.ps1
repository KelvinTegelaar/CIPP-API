function Get-CIPPVersionHistory {
    <#
    .SYNOPSIS
        Returns recorded version-transition events, newest first.
    .DESCRIPTION
        Reads the VersionHistory table written by Update-CIPPVersionHistory at warmup and
        returns the transitions (PreviousVersion, NewVersion, image tags, RecordedAt),
        newest first. Returns an empty array when nothing has been recorded or the table
        cannot be read - the endpoints that surface this treat history as optional
        decoration, so a storage hiccup must not fail them.
    .PARAMETER Last
        Maximum number of events to return. Default 25.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Get-CIPPVersionHistory -Last 10
    #>
    [CmdletBinding()]
    param([int]$Last = 25)

    try {
        $Table = Get-CIPPTable -TableName 'VersionHistory'
        $Events = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'History'"
        return @($Events | Sort-Object -Property RecordedAt -Descending | Select-Object -First $Last | ForEach-Object {
                [PSCustomObject]@{
                    PreviousVersion  = $_.PreviousVersion
                    NewVersion       = $_.NewVersion
                    PreviousImageTag = $_.PreviousImageTag
                    ImageTag         = $_.ImageTag
                    RecordedAt       = $_.RecordedAt
                }
            })
    } catch {
        Write-Information "Could not read version history: $($_.Exception.Message)"
        return @()
    }
}
