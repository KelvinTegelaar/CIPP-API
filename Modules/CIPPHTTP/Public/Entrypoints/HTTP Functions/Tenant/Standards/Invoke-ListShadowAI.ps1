function Invoke-ListShadowAI {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    .DESCRIPTION
        Compiles a Shadow AI overview for a tenant by matching CACHED data from the CIPP reporting
        database (DetectedApps, ServicePrincipals, OAuth2PermissionGrants) against the curated AI
        catalog (Config/ShadowAI.json). No live Graph enumeration is performed - refresh the data by
        syncing those caches (ExecCIPPDBCache). The only live call is a bounded, best-effort 7-day
        sign-in lookup for the matched AI applications.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

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
    $CacheTypes = @('DetectedApps', 'ServicePrincipals', 'OAuth2PermissionGrants')
    $CacheData = @{}
    $CacheTimestamps = [System.Collections.Generic.List[object]]::new()
    foreach ($Type in $CacheTypes) {
        try {
            $CacheData[$Type] = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type)
        } catch {
            $CacheData[$Type] = @()
        }
        try {
            $CountRow = Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type -CountsOnly | Select-Object -First 1
            if ($CountRow.Timestamp) { $CacheTimestamps.Add($CountRow.Timestamp) }
        } catch {}
    }
    $IntuneSynced = $CacheData['DetectedApps'].Count -gt 0
    $EntraSynced = $CacheData['ServicePrincipals'].Count -gt 0
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

    $DetectedApps = [System.Collections.Generic.List[object]]::new()
    foreach ($Entry in $DetectedAppMap.Values) {
        $Match = $Entry.Match
        # Inventory rows mix clean publisher names with full certificate subjects - show the shortest
        $Publisher = $Entry.Publishers | Sort-Object -Property Length | Select-Object -First 1
        $DetectedApps.Add([PSCustomObject]@{
                application     = ($Entry.Applications | Sort-Object) -join ', '
                aiTool          = $Match.name
                vendor          = $Match.vendor
                category        = $Match.category
                risk            = if ($Entry.Sanctioned) { 'Informational' } else { $Match.risk }
                catalogRisk     = $Match.risk
                status          = if ($Entry.Sanctioned) { 'Sanctioned' } else { 'Unsanctioned' }
                toolDescription = $Match.description
                riskReason      = $Match.riskReason
                publisher       = $Publisher
                version         = ($Entry.Versions | Sort-Object) -join ', '
                platform        = ($Entry.Platforms | Sort-Object) -join ', '
                deviceCount     = $Entry.Devices.Count
                managedDevices  = @($Entry.Devices.Values)
            })
    }

    # 2) AI applications in Entra: match ALL cached service principals (not only those with
    #    delegated grants), then attach any granted permissions. First consented = when the
    #    service principal was created in the tenant (the oauth2 grant startTime is unreliable).
    $GrantsBySp = @{}
    foreach ($Grant in $CacheData['OAuth2PermissionGrants']) {
        if (-not $Grant.clientId) { continue }
        if (-not $GrantsBySp.ContainsKey($Grant.clientId)) {
            $GrantsBySp[$Grant.clientId] = [System.Collections.Generic.List[object]]::new()
        }
        $GrantsBySp[$Grant.clientId].Add($Grant)
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

    # --- Roll up distinct AI tools across BOTH sources for the summary and charts ---
    $ToolMap = @{}
    foreach ($App in $DetectedApps) {
        if (-not $ToolMap.ContainsKey($App.aiTool)) {
            $ToolMap[$App.aiTool] = [PSCustomObject]@{ Tool = $App.aiTool; Category = $App.category; Risk = $App.risk; Status = $App.status; Devices = 0; Users = 0 }
        }
        $ToolMap[$App.aiTool].Devices += $App.deviceCount
    }
    foreach ($App in $ConsentedApps) {
        if (-not $ToolMap.ContainsKey($App.aiTool)) {
            $ToolMap[$App.aiTool] = [PSCustomObject]@{ Tool = $App.aiTool; Category = $App.category; Risk = $App.risk; Status = $App.status; Devices = 0; Users = 0 }
        }
        $ToolMap[$App.aiTool].Users += [int]$App.activeUsersLast7Days
    }

    $ByCategory = foreach ($Group in ($ToolMap.Values | Group-Object Category)) {
        [PSCustomObject]@{
            category = $Group.Name
            tools    = $Group.Count
            devices  = [int](($Group.Group | Measure-Object -Property Devices -Sum).Sum)
        }
    }
    $ByRisk = foreach ($Group in ($ToolMap.Values | Group-Object Risk)) {
        [PSCustomObject]@{
            risk  = $Group.Name
            tools = $Group.Count
        }
    }
    # Top tools across BOTH sources: device installs (Intune) + active users (Entra, last 7 days).
    $TopTools = $ToolMap.Values | Sort-Object -Property { $_.Devices + $_.Users } -Descending | Select-Object -First 8 | ForEach-Object {
        [PSCustomObject]@{
            tool      = $_.Tool
            devices   = $_.Devices
            users     = $_.Users
            footprint = $_.Devices + $_.Users
            category  = $_.Category
            status    = $_.Status
        }
    }

    $Body = [PSCustomObject]@{
        summary       = [PSCustomObject]@{
            aiToolsDetected = $ToolMap.Count
            deviceInstalls  = [int](($DetectedApps | Measure-Object -Property deviceCount -Sum).Sum)
            consentedAiApps = $ConsentedApps.Count
            highRiskTools   = @($ToolMap.Values | Where-Object { $_.Risk -eq 'High' }).Count
            sanctionedTools = @($ToolMap.Values | Where-Object { $_.Status -eq 'Sanctioned' }).Count
            intuneSynced    = $IntuneSynced
            entraSynced     = $EntraSynced
            lastDataRefresh = $LastDataRefresh
        }
        byCategory    = @($ByCategory)
        byRisk        = @($ByRisk)
        topTools      = @($TopTools)
        detectedApps  = @($DetectedApps)
        consentedApps = @($ConsentedApps)
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
