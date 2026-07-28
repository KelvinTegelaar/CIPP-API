function Get-CIPPAlertNewShadowAITool {
    <#
    .SYNOPSIS
        Alert on AI tools detected in the tenant for the first time
    .DESCRIPTION
        Matches the cached Intune detected apps and Entra service principals against the curated
        Shadow AI catalog (Config/ShadowAI.json) and alerts when an AI tool shows up that has never
        been seen in this tenant before. The first run stores a baseline and does not alert. Uses
        the same cached data as the Shadow AI dashboard, so the alert only sees what the Detected
        Apps and Service Principals caches contain.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        $Catalog = @(Get-Content (Join-Path $env:CIPPRootPath 'Config\ShadowAI.json') -ErrorAction Stop | ConvertFrom-Json)

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
            Write-Information "Could not load sanctioned AI tools for $($TenantFilter): $($_.Exception.Message)"
        }

        $DetectedApps = @()
        $ServicePrincipals = @()
        try { $DetectedApps = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'DetectedApps') } catch {}
        try { $ServicePrincipals = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ServicePrincipals') } catch {}

        # No cached data at all means the caches have not synced (yet) - leave the baseline
        # untouched instead of treating every tool as gone and re-alerting when data returns.
        if ($DetectedApps.Count -eq 0 -and $ServicePrincipals.Count -eq 0) {
            return
        }

        $CurrentTools = @{}
        foreach ($App in $DetectedApps) {
            $Match = Get-AiMatch -Text "$($App.displayName) $($App.publisher)" -Catalog $Catalog
            if (-not $Match) { continue }
            if (-not $CurrentTools.ContainsKey($Match.name)) {
                $CurrentTools[$Match.name] = [PSCustomObject]@{
                    Match        = $Match
                    Sources      = [System.Collections.Generic.List[string]]::new()
                    Applications = [System.Collections.Generic.List[string]]::new()
                    Devices      = [System.Collections.Generic.HashSet[string]]::new()
                }
            }
            $Entry = $CurrentTools[$Match.name]
            if ($Entry.Sources -notcontains 'Intune device install') { $Entry.Sources.Add('Intune device install') }
            if ($App.displayName -and $Entry.Applications -notcontains [string]$App.displayName) { $Entry.Applications.Add([string]$App.displayName) }
            foreach ($Device in @($App.managedDevices ?? @())) {
                $DeviceKey = if ($Device.id) { [string]$Device.id } else { [string]$Device.deviceName }
                if ($DeviceKey) { $null = $Entry.Devices.Add($DeviceKey) }
            }
        }
        foreach ($Sp in $ServicePrincipals) {
            $Match = Get-AiMatch -Text $Sp.displayName -Catalog $Catalog
            if (-not $Match) { continue }
            if (-not $CurrentTools.ContainsKey($Match.name)) {
                $CurrentTools[$Match.name] = [PSCustomObject]@{
                    Match        = $Match
                    Sources      = [System.Collections.Generic.List[string]]::new()
                    Applications = [System.Collections.Generic.List[string]]::new()
                    Devices      = [System.Collections.Generic.HashSet[string]]::new()
                }
            }
            $Entry = $CurrentTools[$Match.name]
            if ($Entry.Sources -notcontains 'Entra consented application') { $Entry.Sources.Add('Entra consented application') }
            if ($Sp.displayName -and $Entry.Applications -notcontains [string]$Sp.displayName) { $Entry.Applications.Add([string]$Sp.displayName) }
        }

        # Baseline of every tool EVER seen in this tenant - append-only, so a tool that
        # disappears from the cache and comes back does not re-alert.
        $DeltaTable = Get-CIPPTable -Table DeltaCompare
        $Filter = "PartitionKey eq 'ShadowAIDelta' and RowKey eq '{0}'" -f $TenantFilter
        $PreviousRow = Get-CIPPAzDataTableEntity @DeltaTable -Filter $Filter
        $SeenTools = @{}
        if ($PreviousRow.delta) {
            foreach ($Name in @($PreviousRow.delta | ConvertFrom-Json -ErrorAction SilentlyContinue)) {
                if ($Name) { $SeenTools[[string]$Name] = $true }
            }
        }

        $NewToolNames = @($CurrentTools.Keys | Where-Object { -not $SeenTools.ContainsKey($_) })

        $AllSeen = @(@($SeenTools.Keys) + @($CurrentTools.Keys) | Sort-Object -Unique)
        $DeltaEntity = @{
            PartitionKey = 'ShadowAIDelta'
            RowKey       = [string]$TenantFilter
            delta        = [string](ConvertTo-Json -InputObject $AllSeen -Compress)
        }
        Add-CIPPAzDataTableEntity @DeltaTable -Entity $DeltaEntity -Force

        # First run establishes the baseline without alerting.
        if (-not $PreviousRow) { return }

        # Optionally skip tools that are marked as sanctioned for this tenant.
        if ($InputValue -eq $true) {
            $NewToolNames = @($NewToolNames | Where-Object { -not $SanctionedTools.ContainsKey($_.ToLower()) })
        }

        if ($NewToolNames.Count -gt 0) {
            $AlertData = foreach ($ToolName in $NewToolNames) {
                $Info = $CurrentTools[$ToolName]
                [PSCustomObject]@{
                    'AI Tool'      = $Info.Match.name
                    'Vendor'       = $Info.Match.vendor
                    'Category'     = $Info.Match.category
                    'Risk'         = $Info.Match.risk
                    'Status'       = if ($SanctionedTools.ContainsKey($ToolName.ToLower())) { 'Sanctioned' } else { 'Unsanctioned' }
                    'Detected Via' = $Info.Sources -join ', '
                    'Applications' = ($Info.Applications | Sort-Object) -join ', '
                    'Devices'      = $Info.Devices.Count
                    'Tenant'       = $TenantFilter
                }
            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Could not check for new Shadow AI tools for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
