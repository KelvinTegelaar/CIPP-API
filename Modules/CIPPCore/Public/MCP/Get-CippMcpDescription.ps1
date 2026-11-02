function Get-CippMcpDescription {
    <#
    .SYNOPSIS
        Cleans an OpenAPI operation description (strips leaked PowerShell help) and prefixes the tag.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Operation)

    $Desc = [string]$Operation['description']
    $Desc = $Desc -replace '(?s)\s*#>.*$', ''
    $Desc = $Desc -replace '(?s)\[CmdletBinding.*$', ''
    $Desc = $Desc.Trim()
    if ([string]::IsNullOrWhiteSpace($Desc)) { $Desc = [string]$Operation['summary'] }

    $Tag = @($Operation['tags'])[0]
    if ($Tag -and $Tag -ne 'Uncategorized') { $Desc = "[$Tag] $Desc" }
    return $Desc
}
