function Get-CIPPBecUserGrants {
    <#
    .SYNOPSIS
        Collects the investigated user's own OAuth consent grants and enterprise-app role assignments.
    .DESCRIPTION
        Reads users/{id}/oauth2PermissionGrants and users/{id}/appRoleAssignments, resolves the client
        and resource service principals, and flags each entry when it carries a high-risk delegated
        scope from an unverified, non-Microsoft publisher or when the application matches the rogue-app
        catalog (CIPP MaliciousApps.json + Huntress). Consent-based access survives a password reset,
        which is why this check exists. Metadata only: application identity, scopes and publisher.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The user's object id.
    .PARAMETER Heuristics
        The BEC heuristics object (riskyScopes regex + catalogNames).
    .PARAMETER RogueAppFeed
        Output of Get-CIPPBecRogueAppFeed. Fetched when not supplied.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)]$Heuristics,
        $RogueAppFeed
    )

    if (-not $RogueAppFeed) { $RogueAppFeed = Get-CIPPBecRogueAppFeed }
    $Catalog = $RogueAppFeed.Apps
    $ScopeRegex = [string]$Heuristics.riskyScopes.regex
    $CatalogScopes = @($Heuristics.riskyScopes.catalogNames)
    # Microsoft's own multi-tenant apps are owned by these tenants; they are never "unverified third parties".
    $MicrosoftTenantIds = @('f8cdef31-a31e-4b4a-93e4-5f571e91255a', '72f988bf-86f1-41af-91ab-2d7cd011db47')

    $Requests = @(
        @{ id = 'Grants'; method = 'GET'; url = "users/$UserId/oauth2PermissionGrants" }
        @{ id = 'AppRoles'; method = 'GET'; url = "users/$UserId/appRoleAssignments" }
    )
    $Responses = New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true
    $Errors = [System.Collections.Generic.List[string]]::new()
    $GrantResponse = $Responses | Where-Object { $_.id -eq 'Grants' } | Select-Object -First 1
    $AppRoleResponse = $Responses | Where-Object { $_.id -eq 'AppRoles' } | Select-Object -First 1
    foreach ($Pair in @(@{ Name = 'oauth2PermissionGrants'; Response = $GrantResponse }, @{ Name = 'appRoleAssignments'; Response = $AppRoleResponse })) {
        if (-not $Pair.Response) { $Errors.Add("$($Pair.Name) query returned no response") }
        elseif ([int]$Pair.Response.status -ge 400) { $Errors.Add("$($Pair.Name): $($Pair.Response.body.error.message ?? "status $($Pair.Response.status)")") }
    }
    $Grants = @(if ($GrantResponse -and [int]$GrantResponse.status -lt 400) { $GrantResponse.body.value } else { @() })
    $AppRoles = @(if ($AppRoleResponse -and [int]$AppRoleResponse.status -lt 400) { $AppRoleResponse.body.value } else { @() })

    # Resolve every service principal referenced (client + resource) in chunks of 15 ids per filter.
    $SpIds = @(@($Grants.clientId) + @($Grants.resourceId) + @($AppRoles.resourceId) | Where-Object { $_ } | Select-Object -Unique)
    $ServicePrincipals = @{}
    if ($SpIds.Count -gt 0) {
        $SpRequests = for ($i = 0; $i -lt $SpIds.Count; $i += 15) {
            $Chunk = $SpIds[$i..([Math]::Min($i + 14, $SpIds.Count - 1))]
            @{
                id     = "sp$i"
                method = 'GET'
                url    = "servicePrincipals?`$filter=id in ('$($Chunk -join "','")')&`$select=id,appId,displayName,publisherName,verifiedPublisher,appOwnerOrganizationId,accountEnabled,createdDateTime,servicePrincipalType"
            }
        }
        try {
            $SpResponses = New-GraphBulkRequest -Requests @($SpRequests) -tenantid $TenantFilter -asapp $true
            foreach ($Response in $SpResponses) {
                if ([int]$Response.status -ge 400) { $Errors.Add("servicePrincipal lookup: $($Response.body.error.message)"); continue }
                foreach ($Sp in @($Response.body.value)) { if ($Sp.id) { $ServicePrincipals[[string]$Sp.id] = $Sp } }
            }
        } catch {
            $Errors.Add("servicePrincipal lookup failed: $($_.Exception.Message)")
        }
    }

    $Describe = {
        param($Sp)
        $AppId = if ($Sp.appId) { ([string]$Sp.appId).ToLowerInvariant() } else { $null }
        $Match = if ($AppId -and $Catalog.ContainsKey($AppId)) { $Catalog[$AppId] } else { $null }
        [pscustomobject]@{
            DisplayName            = $Sp.displayName
            AppId                  = $Sp.appId
            Publisher              = $Sp.publisherName
            PublisherVerified      = [bool]($Sp.verifiedPublisher.verifiedPublisherId)
            AppOwnerOrganizationId = $Sp.appOwnerOrganizationId
            IsMicrosoft            = ($Sp.appOwnerOrganizationId -in $MicrosoftTenantIds)
            AccountEnabled         = $Sp.accountEnabled
            CreatedDateTime        = $Sp.createdDateTime
            CatalogMatch           = if ($Match) { [pscustomobject]@{ Name = $Match.Name; Source = $Match.Source; Categories = @($Match.Categories); Description = $Match.Description } } else { $null }
        }
    }

    $Rows = [System.Collections.Generic.List[object]]::new()
    foreach ($Grant in $Grants) {
        $Client = & $Describe ($ServicePrincipals[[string]$Grant.clientId])
        $Resource = $ServicePrincipals[[string]$Grant.resourceId]
        $Scopes = @(([string]$Grant.scope) -split '\s+' | Where-Object { $_ })
        $HighRisk = @($Scopes | Where-Object { ($ScopeRegex -and $_ -match $ScopeRegex) -or ($_ -in $CatalogScopes) })
        $Risk = if ($Client.CatalogMatch) { 'CatalogMatch' } elseif ($HighRisk.Count -gt 0 -and -not $Client.PublisherVerified -and -not $Client.IsMicrosoft) { 'High' } elseif ($HighRisk.Count -gt 0) { 'Review' } else { 'Low' }
        $Rows.Add([pscustomobject]@{
                Type                     = 'DelegatedGrant'
                Id                       = $Grant.id
                ConsentType              = $Grant.consentType
                ClientDisplayName        = $Client.DisplayName
                ClientAppId              = $Client.AppId
                ClientServicePrincipalId = $Grant.clientId
                Publisher                = $Client.Publisher
                PublisherVerified        = $Client.PublisherVerified
                IsMicrosoft              = $Client.IsMicrosoft
                ClientAccountEnabled     = $Client.AccountEnabled
                ClientCreatedDateTime    = $Client.CreatedDateTime
                ResourceDisplayName      = $Resource.displayName
                ResourceId               = $Grant.resourceId
                Scope                    = $Grant.scope
                HighRiskScopes           = $HighRisk
                CatalogMatch             = $Client.CatalogMatch
                Risk                     = $Risk
                Flagged                  = ($Risk -in @('CatalogMatch', 'High'))
            })
    }
    foreach ($Assignment in $AppRoles) {
        $Resource = & $Describe ($ServicePrincipals[[string]$Assignment.resourceId])
        $Risk = if ($Resource.CatalogMatch) { 'CatalogMatch' } else { 'Low' }
        $Rows.Add([pscustomobject]@{
                Type                     = 'AppRoleAssignment'
                Id                       = $Assignment.id
                ConsentType              = $null
                ClientDisplayName        = $Assignment.resourceDisplayName ?? $Resource.DisplayName
                ClientAppId              = $Resource.AppId
                ClientServicePrincipalId = $Assignment.resourceId
                Publisher                = $Resource.Publisher
                PublisherVerified        = $Resource.PublisherVerified
                IsMicrosoft              = $Resource.IsMicrosoft
                ClientAccountEnabled     = $Resource.AccountEnabled
                ClientCreatedDateTime    = $Assignment.createdDateTime
                ResourceDisplayName      = $Assignment.resourceDisplayName
                ResourceId               = $Assignment.resourceId
                Scope                    = $Assignment.appRoleId
                HighRiskScopes           = @()
                CatalogMatch             = $Resource.CatalogMatch
                Risk                     = $Risk
                Flagged                  = ($Risk -eq 'CatalogMatch')
            })
    }

    $Data = @($Rows | Sort-Object -Property @{ Expression = { $_.Flagged }; Descending = $true }, ClientDisplayName)
    $ErrorText = if ($Errors.Count -gt 0) { $Errors -join '; ' } else { $null }
    return New-CIPPBecCollectorResult -Data $Data -Complete ($Errors.Count -eq 0) -Error $ErrorText
}
