function Get-CIPPShadowAIReport {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        The Shadow AI overview for a tenant, compiled from the CIPP reporting cache.
    .DESCRIPTION
        Matches the cached DetectedApps, ServicePrincipals and OAuth2PermissionGrants datasets against
        the curated AI catalog (Config/ShadowAI.json) into the shape the Shadow AI page (ListShadowAI)
        and the Shadow AI PDF consume: a summary, tools by category and risk, the top tools across both
        sources, the AI software found on managed devices and the AI applications in Entra. No live
        Graph enumeration is performed (refresh via ExecCIPPDBCache); the only live call is a bounded,
        best-effort 7-day sign-in lookup for the matched AI applications.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    # Curated, PR-editable catalog of known AI tools/apps.
    try {
        $Catalog = @(Get-Content (Join-Path $env:CIPPRootPath 'Config\ShadowAI.json') -ErrorAction Stop | ConvertFrom-Json)
    } catch {
        Write-LogMessage -API 'ShadowAI' -tenant $TenantFilter -message "Could not load Shadow AI catalog. Error: $($_.Exception.Message)" -Sev 'Error'
        $Catalog = @()
    }

    # Returns the first catalog entry whose matchNames appear (case-insensitive substring) in $Text.
    function Get-AiMatch {
        param($Text, $Catalog)
        if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
        $Haystack = $Text.ToLower()
        foreach ($Entry in $Catalog) {
            foreach ($Match in $Entry.matchNames) {
                if ($Match -and $Haystack.Contains($Match.ToLower())) { return $Entry }
            }
        }
        return $null
    }

    $SanctionedTools = @{}
    try {
        $SanctionTable = Get-CIPPTable -TableName 'ShadowAIConfig'
        $EscapedTenant = $TenantFilter -replace "'", "''"
        foreach ($Row in @(Get-CIPPAzDataTableEntity @SanctionTable -Filter "PartitionKey eq '$EscapedTenant'")) {
            $ToolName = if ($Row.Tool) { $Row.Tool } else { $Row.RowKey }
            if ($ToolName) { $SanctionedTools[$ToolName.ToLower()] = $true }
        }
    } catch {
        Write-LogMessage -API 'ShadowAI' -tenant $TenantFilter -message "Could not load sanctioned AI tools: $($_.Exception.Message)" -Sev 'Warning'
    }

    # --- Cached datasets from the CIPP reporting database (no live Graph enumeration) ---
    $CacheData = @{}
    $CacheTimestamps = [System.Collections.Generic.List[object]]::new()
    foreach ($Type in @('DetectedApps', 'ServicePrincipals', 'OAuth2PermissionGrants')) {
        $CacheData[$Type] = try { @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type) } catch { @() }
        $CountRow = try { Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type -CountsOnly | Select-Object -First 1 } catch { $null }
        if ($CountRow.Timestamp) { $CacheTimestamps.Add($CountRow.Timestamp) }
    }
    $LastDataRefresh = $CacheTimestamps | Sort-Object | Select-Object -First 1

    # 1) Installed AI tools from the cached Intune detected apps. The inventory reports a separate
    #    application entry per version (and per install flavor, e.g. 'Copilot' vs 'Microsoft.Copilot'),
    #    so merge everything that matches the same catalog tool into ONE row: distinct devices only,
    #    with the observed application names, versions and platforms combined.
    $DetectedAppMap = [ordered]@{}
    foreach ($App in $CacheData['DetectedApps']) {
        $Match = Get-AiMatch -Text "$($App.displayName) $($App.publisher)" -Catalog $Catalog
        if (-not $Match) { continue }
        if (-not $DetectedAppMap.Contains($Match.name)) {
            $DetectedAppMap[$Match.name] = [PSCustomObject]@{
                Match        = $Match
                Sanctioned   = $SanctionedTools.ContainsKey($Match.name.ToLower())
                Applications = [System.Collections.Generic.List[string]]::new()
                Publishers   = [System.Collections.Generic.List[string]]::new()
                Versions     = [System.Collections.Generic.List[string]]::new()
                Platforms    = [System.Collections.Generic.List[string]]::new()
                Devices      = [ordered]@{}
            }
        }
        $Entry = $DetectedAppMap[$Match.name]
        if ($App.displayName -and $Entry.Applications -notcontains [string]$App.displayName) { $Entry.Applications.Add([string]$App.displayName) }
        if ($App.publisher -and $Entry.Publishers -notcontains [string]$App.publisher) { $Entry.Publishers.Add([string]$App.publisher) }
        if ($App.version -and $Entry.Versions -notcontains [string]$App.version) { $Entry.Versions.Add([string]$App.version) }
        $Platform = if ([string]::IsNullOrWhiteSpace($App.platform)) { 'Unknown' } else { [string]$App.platform }
        if ($Entry.Platforms -notcontains $Platform) { $Entry.Platforms.Add($Platform) }
        foreach ($Device in @($App.managedDevices ?? @())) {
            $DeviceKey = if ($Device.id) { [string]$Device.id } else { [string]$Device.deviceName }
            if ($DeviceKey -and -not $Entry.Devices.Contains($DeviceKey)) { $Entry.Devices[$DeviceKey] = $Device }
        }
    }

    $DetectedApps = @(foreach ($Entry in $DetectedAppMap.Values) {
            $Match = $Entry.Match
            [PSCustomObject]@{
                application     = ($Entry.Applications | Sort-Object) -join ', '
                aiTool          = $Match.name
                vendor          = $Match.vendor
                category        = $Match.category
                risk            = if ($Entry.Sanctioned) { 'Informational' } else { $Match.risk }
                catalogRisk     = $Match.risk
                status          = if ($Entry.Sanctioned) { 'Sanctioned' } else { 'Unsanctioned' }
                toolDescription = $Match.description
                riskReason      = $Match.riskReason
                # Inventory rows mix clean publisher names with full certificate subjects - show the shortest.
                publisher       = $Entry.Publishers | Sort-Object -Property Length | Select-Object -First 1
                version         = ($Entry.Versions | Sort-Object) -join ', '
                platform        = ($Entry.Platforms | Sort-Object) -join ', '
                deviceCount     = $Entry.Devices.Count
                managedDevices  = @($Entry.Devices.Values)
            }
        })

    # 2) AI applications in Entra: match ALL cached service principals (not only those with
    #    delegated grants), then attach any granted permissions. First consented = when the
    #    service principal was created in the tenant (the oauth2 grant startTime is unreliable).
    $GrantsBySp = @{}
    foreach ($Group in ($CacheData['OAuth2PermissionGrants'] | Where-Object { $_.clientId } | Group-Object clientId)) {
        $GrantsBySp[$Group.Name] = $Group.Group
    }

    $ConsentedApps = [System.Collections.Generic.List[object]]::new()
    $SeenApps = @{}
    foreach ($Sp in $CacheData['ServicePrincipals']) {
        $Match = Get-AiMatch -Text $Sp.displayName -Catalog $Catalog
        if (-not $Match) { continue }
        $Key = [string]($Sp.appId ?? $Sp.id)
        if ($SeenApps.ContainsKey($Key)) { continue }
        # Individual scopes as a string array so the frontend renders them as chips.
        $Permissions = if ($GrantsBySp.ContainsKey($Sp.id)) {
            @((@($GrantsBySp[$Sp.id].scope) -join ' ') -split '\s+' | Where-Object { $_ } | Sort-Object -Unique)
        } else {
            @()
        }
        $IsSanctioned = $SanctionedTools.ContainsKey($Match.name.ToLower())
        $Consent = [PSCustomObject]@{
            application            = $Sp.displayName
            aiTool                 = $Match.name
            vendor                 = $Match.vendor
            category               = $Match.category
            risk                   = if ($IsSanctioned) { 'Informational' } else { $Match.risk }
            catalogRisk            = $Match.risk
            status                 = if ($IsSanctioned) { 'Sanctioned' } else { 'Unsanctioned' }
            toolDescription        = $Match.description
            riskReason             = $Match.riskReason
            applicationId          = $Sp.appId
            approvedPermissions    = @($Permissions)
            firstConsentedDateTime = $Sp.createdDateTime
            signInsLast7Days       = 0
            activeUsersLast7Days   = 0
            applicationUsers       = @()
        }
        $SeenApps[$Key] = $Consent
        $ConsentedApps.Add($Consent)
    }

    # 2b) Best-effort: recent sign-in usage (last 7 days) for the matched AI apps. This is the only
    #     live Graph call: a single bounded query, skipped gracefully when unavailable (needs P1).
    $AiAppIds = @($ConsentedApps.applicationId | Where-Object { $_ } | Select-Object -Unique -First 15)
    if ($AiAppIds.Count -gt 0) {
        try {
            $StartDate = (Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            $AppFilter = ($AiAppIds | ForEach-Object { "appId eq '$_'" }) -join ' or '
            $SignInFilter = "createdDateTime ge $StartDate and ($AppFilter)"
            $SignIns = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=$SignInFilter" -tenantid $TenantFilter
            $SignInGroups = $SignIns | Group-Object appId
            foreach ($Consent in $ConsentedApps) {
                $Group = $SignInGroups | Where-Object { $_.Name -eq $Consent.applicationId }
                if ($Group) {
                    $Consent.signInsLast7Days = $Group.Count
                    $Consent.activeUsersLast7Days = @($Group.Group.userId | Select-Object -Unique).Count
                    $Consent.applicationUsers = @($Group.Group | Group-Object userPrincipalName | ForEach-Object {
                            [PSCustomObject]@{
                                userPrincipalName  = $_.Name
                                userDisplayName    = ($_.Group | Select-Object -First 1).userDisplayName
                                signIns            = $_.Count
                                lastSignInDateTime = ($_.Group.createdDateTime | Sort-Object -Descending | Select-Object -First 1)
                            }
                        })
                }
            }
        } catch {
            Write-LogMessage -API 'ShadowAI' -tenant $TenantFilter -message "Sign-in usage enrichment skipped (requires Entra ID P1). Error: $($_.Exception.Message)" -Sev 'Info'
        }
    }

    # --- Roll up distinct AI tools across BOTH sources for the summary and charts: device installs
    #     from the Intune rows, active users (last 7 days) from the Entra rows, the first row seen
    #     (Intune first) naming the tool's category, risk and status. ---
    $Tools = @($DetectedApps + @($ConsentedApps) | Group-Object aiTool | ForEach-Object {
            [PSCustomObject]@{
                Tool     = $_.Name
                Category = $_.Group[0].category
                Risk     = $_.Group[0].risk
                Status   = $_.Group[0].status
                Devices  = [int](($_.Group | ForEach-Object { [int]($_.deviceCount ?? 0) } | Measure-Object -Sum).Sum)
                Users    = [int](($_.Group | ForEach-Object { [int]($_.activeUsersLast7Days ?? 0) } | Measure-Object -Sum).Sum)
            }
        })

    # Built as @(...) so a tenant with no AI tools gets empty lists, not a single null entry.
    $ByCategory = @(foreach ($Group in ($Tools | Group-Object Category)) {
            [PSCustomObject]@{
                category = $Group.Name
                tools    = $Group.Count
                devices  = [int](($Group.Group | Measure-Object -Property Devices -Sum).Sum)
            }
        })
    $ByRisk = @(foreach ($Group in ($Tools | Group-Object Risk)) {
            [PSCustomObject]@{
                risk  = $Group.Name
                tools = $Group.Count
            }
        })
    # Top tools across BOTH sources: device installs (Intune) + active users (Entra, last 7 days).
    $TopTools = @($Tools | Sort-Object -Property { $_.Devices + $_.Users } -Descending | Select-Object -First 8 | ForEach-Object {
            [PSCustomObject]@{
                tool      = $_.Tool
                devices   = $_.Devices
                users     = $_.Users
                footprint = $_.Devices + $_.Users
                category  = $_.Category
                status    = $_.Status
            }
        })

    $Body = [PSCustomObject]@{
        summary       = [PSCustomObject]@{
            aiToolsDetected = $Tools.Count
            deviceInstalls  = [int](($DetectedApps | Measure-Object -Property deviceCount -Sum).Sum)
            consentedAiApps = $ConsentedApps.Count
            highRiskTools   = @($Tools | Where-Object { $_.Risk -eq 'High' }).Count
            sanctionedTools = @($Tools | Where-Object { $_.Status -eq 'Sanctioned' }).Count
            intuneSynced    = $CacheData['DetectedApps'].Count -gt 0
            entraSynced     = $CacheData['ServicePrincipals'].Count -gt 0
            lastDataRefresh = $LastDataRefresh
        }
        byCategory    = @($ByCategory)
        byRisk        = @($ByRisk)
        topTools      = @($TopTools)
        detectedApps  = @($DetectedApps)
        consentedApps = @($ConsentedApps)
    }
    return $Body
}
