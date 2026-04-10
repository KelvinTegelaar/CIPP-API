function Get-AlertContentHash {
    <#
    .SYNOPSIS
        Generate a stable hash from an alert item for snooze matching.
    .DESCRIPTION
        Uses a priority list of fields (UserPrincipalName > Id > Message) to produce a
        deterministic identifier. Falls back to full sorted-JSON if none of the priority
        fields exist. Returns both the hash and the raw key value used.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $AlertItem
    )

    # Convert to hashtable if PSCustomObject for uniform access
    $ItemHash = if ($AlertItem -is [hashtable]) {
        $AlertItem
    } elseif ($AlertItem -is [System.Collections.Specialized.OrderedDictionary]) {
        $AlertItem
    } else {
        $ht = @{}
        foreach ($prop in $AlertItem.PSObject.Properties) {
            $ht[$prop.Name] = $prop.Value
        }
        $ht
    }

    # Priority field selection for stable hashing
    $RawKey = $null
    if ($ItemHash.ContainsKey('UserPrincipalName') -and -not [string]::IsNullOrWhiteSpace($ItemHash['UserPrincipalName'])) {
        $RawKey = $ItemHash['UserPrincipalName'].ToString().Trim().ToLowerInvariant()
    } elseif ($ItemHash.ContainsKey('Id') -and -not [string]::IsNullOrWhiteSpace($ItemHash['Id'])) {
        $RawKey = $ItemHash['Id'].ToString().Trim().ToLowerInvariant()
    } elseif ($ItemHash.ContainsKey('Message') -and -not [string]::IsNullOrWhiteSpace($ItemHash['Message'])) {
        $RawKey = $ItemHash['Message'].ToString().Trim()
    }

    # Fallback: sort keys and serialize to JSON for a deterministic representation
    if ([string]::IsNullOrWhiteSpace($RawKey)) {
        $SortedKeys = $ItemHash.Keys | Sort-Object
        $Ordered = [ordered]@{}
        foreach ($key in $SortedKeys) {
            $Ordered[$key] = $ItemHash[$key]
        }
        $RawKey = ConvertTo-Json -InputObject $Ordered -Compress -Depth 5 | Out-String
    }

    # Compute SHA256 hash
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($RawKey)
        $hashBytes = $sha256.ComputeHash($bytes)
        $ContentHash = [System.Convert]::ToBase64String($hashBytes)
    } finally {
        $sha256.Dispose()
    }

    return [PSCustomObject]@{
        ContentHash    = $ContentHash
        RawKey         = $RawKey
        ContentPreview = if ($RawKey.Length -gt 200) { $RawKey.Substring(0, 200) } else { $RawKey }
    }
}
