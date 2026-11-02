function Get-CIPPEwsPermissionApps {
    <#
    .SYNOPSIS
        Lists the service principals in a tenant that hold Exchange Online EWS permissions.
    .DESCRIPTION
        Returns one object per app holding the Exchange Online full_access_as_app application
        role, or a delegated grant on Exchange Online that includes EWS.AccessAsUser.All or
        full_access_as_user. Assignments and grants are read live from Graph (the nightly cache
        misses assignments, and an incomplete allow list breaks apps); service principal names
        come from the cache with a live lookup for any holder it lacks.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$TenantFilter
    )

    $ExoAppId = '00000002-0000-0ff1-ce00-000000000000'
    $DelegatedScopes = @('EWS.AccessAsUser.All', 'full_access_as_user')

    $ServicePrincipals = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ServicePrincipals' -Fields 'id', 'appId', 'displayName', 'appRoles')
    if ($ServicePrincipals.Count -eq 0) {
        $ServicePrincipals = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/servicePrincipals?$select=id,appId,displayName,appRoles&$top=999' -tenantid $TenantFilter)
    }
    $ExoSp = $ServicePrincipals | Where-Object { $_.appId -eq $ExoAppId } | Select-Object -First 1
    if (-not $ExoSp.id) { throw 'The Exchange Online service principal was not found.' }
    # Resolve the role by value; the well-known id is only a fallback.
    $FullAccessRoleId = (@($ExoSp.appRoles) | Where-Object { $_.value -eq 'full_access_as_app' } | Select-Object -First 1).id ?? 'dc890d15-9560-4a4c-9b7f-a736ec74ec40'

    $Assignments = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ExoSp.id)/appRoleAssignedTo?`$top=999" -tenantid $TenantFilter)
    $Grants = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/oauth2PermissionGrants?`$filter=resourceId eq '$($ExoSp.id)'" -tenantid $TenantFilter)

    # principalId -> @{ types; permissions }
    $Holders = [ordered]@{}
    $AddHolder = {
        param($SpId, $Type, $Permission)
        if (-not $Holders.Contains($SpId)) {
            $Holders[$SpId] = @{
                Types       = [System.Collections.Generic.List[string]]::new()
                Permissions = [System.Collections.Generic.List[string]]::new()
            }
        }
        if (-not $Holders[$SpId].Types.Contains($Type)) { $Holders[$SpId].Types.Add($Type) }
        if (-not $Holders[$SpId].Permissions.Contains($Permission)) { $Holders[$SpId].Permissions.Add($Permission) }
    }
    foreach ($Assignment in $Assignments) {
        if ($Assignment.resourceId -eq $ExoSp.id -and $Assignment.appRoleId -eq $FullAccessRoleId -and $Assignment.principalType -eq 'ServicePrincipal') {
            & $AddHolder "$($Assignment.principalId)" 'Application' 'full_access_as_app'
        }
    }
    foreach ($Grant in $Grants) {
        if ($Grant.resourceId -ne $ExoSp.id) { continue }
        foreach ($Scope in ("$($Grant.scope)" -split '\s+')) {
            $Match = $DelegatedScopes | Where-Object { $_ -eq $Scope } | Select-Object -First 1
            if ($Match) { & $AddHolder "$($Grant.clientId)" 'Delegated' $Match }
        }
    }
    if ($Holders.Count -eq 0) { return }

    $SpById = @{}
    foreach ($Sp in $ServicePrincipals) { if ($Sp.id) { $SpById["$($Sp.id)"] = $Sp } }
    # Holders the cache does not know yet (apps added since the nightly run): one $batch lookup.
    $LookupRequests = [System.Collections.Generic.List[object]]::new()
    foreach ($SpId in $Holders.Keys) {
        if (-not $SpById.ContainsKey($SpId)) {
            $LookupRequests.Add(@{ id = $SpId; method = 'GET'; url = "servicePrincipals/$SpId`?`$select=id,appId,displayName" })
        }
    }
    if ($LookupRequests.Count -gt 0) {
        foreach ($Result in @(New-GraphBulkRequest -Requests @($LookupRequests) -tenantid $TenantFilter)) {
            if ($Result.status -eq 200 -and $Result.body.id) { $SpById["$($Result.body.id)"] = $Result.body }
        }
    }
    $Malicious = (Get-CIPPBecRogueAppFeed).Apps

    foreach ($SpId in $Holders.Keys) {
        $Sp = $SpById[$SpId]
        if (-not $Sp) { continue }
        $AppId = "$($Sp.appId)".ToLowerInvariant()
        $Holder = $Holders[$SpId]
        $MaliciousEntry = if ($AppId -and $Malicious) { $Malicious[$AppId] }
        [PSCustomObject]@{
            appId               = $AppId
            displayName         = $Sp.displayName
            servicePrincipalId  = $SpId
            permissionType      = $Holder.Types -join ', '
            permissions         = @($Holder.Permissions)
            isExchangeHybridApp = $Holder.Permissions.Contains('full_access_as_app') -and "$($Sp.displayName)" -like 'ExchangeServerApp-*'
            isKnownMalicious    = [bool]$MaliciousEntry
            maliciousName       = $MaliciousEntry.Name
        }
    }
}
