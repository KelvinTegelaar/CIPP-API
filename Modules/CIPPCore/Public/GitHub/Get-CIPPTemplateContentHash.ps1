function Get-CIPPTemplateContentHash {
    <#
    .SYNOPSIS
        Computes a deterministic content hash for a template JSON blob.
    .DESCRIPTION
        Drops the fields that change without a real content edit (tenantFilter,
        excludedTenants, updatedAt/updatedBy, createdAt), then canonicalises the
        remaining object (object keys sorted ordinal, arrays kept in order) before
        hashing, so the same content hashes equal regardless of key order.
    .OUTPUTS
        Lowercase SHA256 hex string, or $null for empty/unparsable input.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$JSON
    )

    if ([string]::IsNullOrWhiteSpace($JSON)) { return $null }

    try {
        $Data = $JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    } catch {
        return $null
    }

    function Get-CIPPCanonicalValue {
        param($Value)

        if ($null -eq $Value) { return $null }

        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            return @($Value | ForEach-Object { Get-CIPPCanonicalValue -Value $_ })
        }

        if ($Value -is [PSCustomObject] -or $Value -is [System.Collections.IDictionary]) {
            $Ordered = [ordered]@{}
            $Keys = @(if ($Value -is [System.Collections.IDictionary]) { $Value.Keys } else { $Value.PSObject.Properties.Name })
            [array]::Sort($Keys, [System.StringComparer]::Ordinal)
            foreach ($Key in $Keys) {
                if ($Key -in @('tenantFilter', 'excludedTenants', 'updatedAt', 'updatedBy', 'createdAt')) { continue }
                $Ordered[$Key] = Get-CIPPCanonicalValue -Value $Value.$Key
            }
            return $Ordered
        }

        return $Value
    }

    $Canonical = Get-CIPPCanonicalValue -Value $Data
    $CompactJSON = $Canonical | ConvertTo-Json -Depth 100 -Compress
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($CompactJSON)
    $HashBytes = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    -join ($HashBytes | ForEach-Object { $_.ToString('x2') })
}
