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

    $AccessIPRangeTable = Get-CippTable -tablename 'AccessIPRanges'

    foreach ($Role in $Roles) {
        try {
            $IPRangeEntity = Get-CIPPAzDataTableEntity @AccessIPRangeTable -Filter "RowKey eq '$($Role.ToLower())'"
            if ($IPRangeEntity -and $IPRangeEntity.IPRanges) {
                $IPRanges = @($IPRangeEntity.IPRanges | ConvertFrom-Json)
                foreach ($IPRange in $IPRanges) {
                    if ($IPRange -and -not $CombinedIPRanges.Contains($IPRange)) {
                        $CombinedIPRanges.Add($IPRange)
                    }
                }
            }
        } catch {
            Write-Information "Failed to get IP ranges for role '$Role': $($_.Exception.Message)"
            continue
        }
    }

    # If no IP ranges were found in any role, allow all
    if ($CombinedIPRanges.Count -eq 0) {
        return @('Any')
    }

    return @($CombinedIPRanges) | Sort-Object -Unique
}
