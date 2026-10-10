function Get-CIPPBaselineUsageLocationState {
    <#
    .SYNOPSIS
        Prepare hook for UsageLocation: member accounts whose usage location is not the
        configured country.
    .DESCRIPTION
        Members only - guests are never licensed through the tenant and their location is
        their own organisation's business. Directory-synced accounts ARE included: usage
        location is cloud-managed and the admin centre lets you set it on synced users, so
        skipping them would leave exactly the accounts a hybrid tenant most needs fixed.

        Group scoping works on display names because a baseline applies to many tenants and
        a group id only exists in one. Names resolve against the Groups cache (collected on a
        miss) and expand LIVE to transitive user members - the cache holds direct members
        only and nothing for dynamic groups, and a nested group's users are still members.
        A name that resolves to no group, or a membership lookup that fails, returns a null
        Current (No Data): sweeping with a half-resolved exclusion list is how an overseas
        office ends up with the wrong country and broken licences.

        'onlyWhenBlank' turns the compare from 'equals the configured country' into 'has any
        value at all', for tenants where locations were set by hand per user.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Users = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users' | Where-Object { $_ })
    if ($Users.Count -eq 0) { return @{ Current = $null } }

    $Wanted = "$($Item.Variables.usageLocation.value ?? $Item.Variables.usageLocation)".Trim().ToUpperInvariant()
    if ($Wanted -notmatch '^[A-Z]{2}$') {
        Write-Information "Baselines: UsageLocation on $TenantFilter has no valid two-letter country code configured ('$Wanted')."
        return @{ Current = $null }
    }
    $OnlyWhenBlank = [bool]($Item.Variables.onlyWhenBlank -eq $true)

    # Picker values arrive flattened by the engine, but a one-off or a test may still hand
    # over the {label, value} wrappers the form saves.
    $ToNames = {
        param($Value)
        @(@($Value) | ForEach-Object {
                if ($_ -is [string]) { $_ } else { "$($_.value ?? $_.label)" }
            } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    }
    $IncludeNames = & $ToNames $Item.Variables.includeGroups
    $ExcludeNames = & $ToNames $Item.Variables.excludeGroups

    $IncludedIds = @{}
    $ExcludedIds = @{}
    if ($IncludeNames.Count -gt 0 -or $ExcludeNames.Count -gt 0) {
        $Groups = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups')
        $GroupIdsByName = @{}
        foreach ($Group in $Groups) {
            $Name = "$($Group.displayName)".Trim()
            if (-not $Name -or -not $Group.id) { continue }
            if (-not $GroupIdsByName.ContainsKey($Name)) { $GroupIdsByName[$Name] = [System.Collections.Generic.List[string]]::new() }
            $GroupIdsByName[$Name].Add("$($Group.id)")
        }
        # Case-insensitive lookup: the hashtable literal above is case-insensitive already,
        # this just makes the intent explicit for the reader.
        $Unresolved = @(@($IncludeNames) + @($ExcludeNames) | Where-Object { -not $GroupIdsByName.ContainsKey($_) })
        if ($Unresolved.Count -gt 0) {
            Write-Information "Baselines: UsageLocation on $TenantFilter cannot resolve group(s) $($Unresolved -join ', ') - refusing to sweep with a partial scope."
            return @{ Current = $null }
        }

        $Requests = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($Name in $IncludeNames) {
            foreach ($GroupId in $GroupIdsByName[$Name]) {
                $Requests.Add(@{ id = "include-$GroupId"; method = 'GET'; url = "groups/$GroupId/transitiveMembers/microsoft.graph.user?`$select=id&`$top=999" })
            }
        }
        foreach ($Name in $ExcludeNames) {
            foreach ($GroupId in $GroupIdsByName[$Name]) {
                $Requests.Add(@{ id = "exclude-$GroupId"; method = 'GET'; url = "groups/$GroupId/transitiveMembers/microsoft.graph.user?`$select=id&`$top=999" })
            }
        }

        try {
            $Responses = @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests) -asapp $true -Version 'v1.0')
        } catch {
            Write-Information "Baselines: UsageLocation group membership lookup on $TenantFilter failed, refusing to sweep: $($_.Exception.Message)"
            return @{ Current = $null }
        }
        foreach ($Response in $Responses) {
            if ([int]$Response.status -lt 200 -or [int]$Response.status -gt 299) {
                Write-Information "Baselines: UsageLocation group membership lookup on $TenantFilter returned $($Response.status) for $($Response.id), refusing to sweep."
                return @{ Current = $null }
            }
            $Bucket = if ("$($Response.id)".StartsWith('include-')) { $IncludedIds } else { $ExcludedIds }
            foreach ($MemberId in @($Response.body.value.id | Where-Object { $_ })) { $Bucket["$MemberId"] = $true }
        }
    }

    $Candidates = @($Users | Where-Object { $_.userType -eq 'Member' -and $_.id })
    if ($IncludeNames.Count -gt 0) { $Candidates = @($Candidates | Where-Object { $IncludedIds.ContainsKey("$($_.id)") }) }
    if ($ExcludeNames.Count -gt 0) { $Candidates = @($Candidates | Where-Object { -not $ExcludedIds.ContainsKey("$($_.id)") }) }

    $Incorrect = @($Candidates | Where-Object {
            $Location = "$($_.usageLocation)".Trim().ToUpperInvariant()
            if ($OnlyWhenBlank) { [string]::IsNullOrWhiteSpace($Location) } else { $Location -ne $Wanted }
        })

    @{
        Current = [PSCustomObject]@{
            offenders = @($Incorrect.userPrincipalName | Sort-Object)
            targets   = @($Incorrect | ForEach-Object { [PSCustomObject]@{ id = "$($_.id)" } })
        }
    }
}
