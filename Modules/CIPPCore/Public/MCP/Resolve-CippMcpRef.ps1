function Resolve-CippMcpRef {
    <#
    .SYNOPSIS
        Resolves a JSON pointer like '#/components/parameters/tenantFilter' against the OpenAPI spec.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([string]$Ref, $Spec)

    $Segments = $Ref.TrimStart('#') -split '/' | Where-Object { $_ -ne '' }
    $Node = $Spec
    foreach ($Seg in $Segments) {
        $Key = $Seg -replace '~1', '/' -replace '~0', '~'
        if ($Node -is [System.Collections.IDictionary] -and $Node.Contains($Key)) {
            $Node = $Node[$Key]
        } else {
            return $null
        }
    }
    return $Node
}
