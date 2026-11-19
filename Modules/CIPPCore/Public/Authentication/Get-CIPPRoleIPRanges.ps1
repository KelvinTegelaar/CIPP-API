function Get-CIPPRoleIPRanges {
    <#
    .SYNOPSIS
        Gets combined IP ranges from a list of roles
    .DESCRIPTION
        This function retrieves IP range restrictions from custom roles and returns a consolidated list.
        Superadmin roles are excluded from IP restrictions.
    .PARAMETER Roles
        Array of role names to check for IP restrictions
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Roles
    )

    $CombinedIPRanges = [System.Collections.Generic.List[string]]::new()

    # Superadmin is never restricted by IP
    if ($Roles -contains 'superadmin') {
        return @('Any')
    }

    # Role-level data only, per worker; a role save bumps the version, the expiry is the backstop
    $Now = [datetime]::UtcNow
    $Version = Get-CippAccessScopeVersion
    if (-not $script:CippRoleIPRangeCache -or $script:CippRoleIPRangeCache.Count -gt 200) {
        $script:CippRoleIPRangeCache = [System.Collections.Generic.Dictionary[string, object]]::new()
    }
    $AccessIPRangeTable = $null

    foreach ($Role in $Roles) {
        try {
            $CacheKey = '{0}|{1}' -f $Version, $Role.ToLower()
            $Cached = $null
            if ($script:CippRoleIPRangeCache.TryGetValue($CacheKey, [ref]$Cached) -and $Cached.Expires -gt $Now) {
                $IPRanges = $Cached.Ranges
            } else {
                $AccessIPRangeTable ??= Get-CippTable -tablename 'AccessIPRanges'
                $IPRangeEntity = Get-CIPPAzDataTableEntity @AccessIPRangeTable -Filter "RowKey eq '$($Role.ToLower())'"
                $IPRanges = if ($IPRangeEntity -and $IPRangeEntity.IPRanges) { @($IPRangeEntity.IPRanges | ConvertFrom-Json) } else { @() }
                $script:CippRoleIPRangeCache[$CacheKey] = @{ Ranges = $IPRanges; Expires = $Now.AddMinutes(5) }
            }
            foreach ($IPRange in $IPRanges) {
                if ($IPRange -and -not $CombinedIPRanges.Contains($IPRange)) {
                    $CombinedIPRanges.Add($IPRange)
                }
            }
        } catch {
            Write-Information "Failed to get IP ranges for role '$Role': $($_.Exception.Message)"
            continue
        }
    }

    if ($CombinedIPRanges.Count -eq 0) {
        return @('Any')
    }

    return @($CombinedIPRanges) | Sort-Object -Unique
}
