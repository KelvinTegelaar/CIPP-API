function ConvertTo-CIPPBaselineOSVersion {
    <#
    .SYNOPSIS
        Parses an OS version string ("18", "18.7.12", "10.0.26100.2605") into a [version] so two can be
        compared. Returns nothing for a blank or non-numeric value.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$Text
    )

    $Text = "$Text".Trim()
    if ($Text -notmatch '^\d{1,9}(\.\d{1,9}){0,3}$') { return }
    $Parts = [int[]]::new(4)
    $Split = $Text -split '\.'
    for ($i = 0; $i -lt $Split.Count; $i++) { $Parts[$i] = [int]$Split[$i] }
    [version]::new($Parts[0], $Parts[1], $Parts[2], $Parts[3])
}
