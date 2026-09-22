function Get-CIPPDriveItemCloudPathLength {
    <#
    .SYNOPSIS
        Returns the decoded library-relative path length for a Graph drive item.

    .DESCRIPTION
        Builds path from parentReference.path + name. Strips the Graph "/.../root:" prefix,
        URL-decodes, and returns character length only — never the path string to callers
        that might persist it. Used for OneDrive long-path counting.

    .PARAMETER ParentPath
        driveItem.parentReference.path (e.g. /drives/{id}/root:/Folder/Sub)

    .PARAMETER Name
        driveItem.name

    .OUTPUTS
        System.Int32
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$ParentPath,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return 0
    }

    $Relative = ''
    if (-not [string]::IsNullOrWhiteSpace($ParentPath)) {
        $Marker = 'root:'
        $Idx = $ParentPath.IndexOf($Marker, [System.StringComparison]::OrdinalIgnoreCase)
        if ($Idx -ge 0) {
            $Relative = $ParentPath.Substring($Idx + $Marker.Length)
        }
    }

    if ([string]::IsNullOrWhiteSpace($Relative) -or $Relative -eq '/') {
        $Combined = $Name
    } else {
        $Combined = $Relative.TrimEnd('/') + '/' + $Name
    }

    $Combined = $Combined.TrimStart('/')

    try {
        $Decoded = [uri]::UnescapeDataString($Combined)
    } catch {
        $Decoded = $Combined
    }

    return $Decoded.Length
}
