function Invoke-ExecGetExecutiveReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    .DESCRIPTION
        Server-renders the Executive Summary report as application/pdf bytes. Every figure is read from the
        nightly Reporting DB cache via New-CIPPDbRequest (Users/Guests/Roles for the environment overview,
        LicenseOverview, ManagedDevices, ConditionalAccessPolicies and SecureScore) plus the standards
        comparison from the CippStandardsReports table resolved against the standards catalog - the same
        cached data the rest of CIPP reports from, with no live Graph or cross-endpoint HTTP calls. The
        shaped data is composed through the shared CIPPSharp component kit (Build-CippExecutiveReportTree),
        the server-side replacement for the client react-pdf ExecutiveReportButton. Each source is gathered
        defensively: a source with no cached data simply drops its section.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -Headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'A tenantFilter is required' })
        }

        # The branding preset a caller picked for this render, else the global branding settings.
        $BrandingPresetId = [string]($Request.Body.brandingPresetId ?? $Request.Query.brandingPresetId)
        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter -BrandingPresetId $BrandingPresetId

        # GA directory role template id, used to pull the Global Administrator count from the Roles cache.
        $GaTemplateId = '62e90394-69f5-4237-9190-012177145e10'

        # -- User stats (Users / Guests cache + the cached privileged-role getter for GAs) --
        $UserStats = @{ licensedUsers = 0; unlicensedUsers = 0; guests = 0; globalAdmins = 0; permanentGlobalAdmins = 0; eligibleGlobalAdmins = 0; pimCapable = $false }
        try {
            $Users = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users' -Fields 'assignedLicenses')
            $LicUsers = @($Users | Where-Object { @($_.assignedLicenses).Count -gt 0 }).Count
            $GuestCount = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Guests' -Fields 'id').Count
            # Get-CippDbRoleMembers merges cached PIM (Active/Eligible) + direct role membership for the role.
            $GaMembers = @(Get-CippDbRoleMembers -TenantFilter $TenantFilter -RoleTemplateId $GaTemplateId)
            $EligibleGas = @($GaMembers | Where-Object { $_.AssignmentType -eq 'Eligible' }).Count
            $PimActive = @($GaMembers | Where-Object { $_.AssignmentType -in @('Active', 'Eligible') }).Count
            $UserStats = @{
                licensedUsers         = $LicUsers
                unlicensedUsers       = [Math]::Max(0, $Users.Count - $LicUsers)
                guests                = $GuestCount
                globalAdmins          = $GaMembers.Count
                permanentGlobalAdmins = ($GaMembers.Count - $EligibleGas)
                eligibleGlobalAdmins  = $EligibleGas
                # PIM is in use for GA when any assignment is a PIM Active/Eligible one (not plain Direct).
                pimCapable            = ($PimActive -gt 0)
            }
        } catch { Write-Information "Executive report: user stats unavailable - $($_.Exception.Message)" }

        # -- Licences (LicenseOverview cache) --
        $Licenses = @()
        try {
            $Licenses = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'LicenseOverview' | ForEach-Object {
                    @{ name = ($_.License ?? 'N/A'); used = "$($_.CountUsed ?? 0)"; available = "$($_.CountAvailable ?? 0)"; total = "$($_.TotalLicenses ?? 0)" }
                })
        } catch { Write-Information "Executive report: licences unavailable - $($_.Exception.Message)" }

        # -- Managed devices (ManagedDevices cache) --
        $Devices = @()
        try {
            $Devices = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ManagedDevices' | ForEach-Object {
                    $d = $_
                    $model = [string]$d.model
                    $mfr = [string]$d.manufacturer
                    $isCloudPc = ($d.isCloudPC -eq $true) -or ($d.deviceType -eq 'cloudPC') -or ($d.chassisType -eq 'cloudPC') -or ($model.ToLower().StartsWith('cloud pc') -and $mfr.ToLower() -eq 'microsoft corporation')
                    $compState = [string]$d.complianceState
                    @{
                        name       = ($d.deviceName ?? 'N/A')
                        os         = ($d.operatingSystem ?? 'N/A')
                        compliance = $(if ([string]::IsNullOrWhiteSpace($compState)) { 'Unknown' } else { $compState })
                        compliant  = ($compState.ToLower() -eq 'compliant')
                        lastSync   = $(if ($d.lastSyncDateTime) { try { ([datetime]$d.lastSyncDateTime).ToString('MMM d, yyyy') } catch { [string]$d.lastSyncDateTime } } else { 'N/A' })
                        encrypted  = (($d.isEncrypted -eq $true) -or $isCloudPc)
                    }
                })
        } catch { Write-Information "Executive report: managed devices unavailable - $($_.Exception.Message)" }

        # -- Conditional Access policies (ConditionalAccessPolicies cache, raw Graph shape) --
        # 'controls' is the builtInControls array (drives the tree's MFA count via -contains 'mfa');
        # 'controlsText' is the human label; 'applications' summarises includeApplications.
        $CAPolicies = @()
        try {
            $ControlLabels = [ordered]@{ mfa = 'MFA'; block = 'Block'; compliantDevice = 'Compliant Device' }
            $CAPolicies = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ConditionalAccessPolicies' | Where-Object { $_.displayName } | ForEach-Object {
                    $p = $_
                    $bic = @($p.grantControls.builtInControls)
                    $apps = @($p.conditions.applications.includeApplications)
                    $labels = @(foreach ($k in $ControlLabels.Keys) { if ($bic -contains $k) { $ControlLabels[$k] } })
                    @{
                        name         = ($p.displayName ?? 'N/A')
                        state        = ([string]$p.state)
                        controls     = $bic
                        controlsText = $(if ($labels.Count -gt 0) { $labels -join ', ' } else { 'Custom' })
                        applications = $(if ($apps -contains 'All') { 'All' } elseif ($apps.Count -gt 0) { "$($apps.Count) app$(if ($apps.Count -ne 1) { 's' })" } else { 'None' })
                    }
                })
        } catch { Write-Information "Executive report: conditional access unavailable - $($_.Exception.Message)" }

        # -- Microsoft Secure Score (SecureScore cache, one record per day) --
        $SecureScore = $null
        try {
            $Scores = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SecureScore' | Sort-Object -Property @{ Expression = { [datetime]$_.createdDateTime } } -Descending)
            if ($Scores.Count -gt 0) {
                $Latest = $Scores[0]
                $Cur = [double]($Latest.currentScore ?? 0)
                $Max = [double]($Latest.maxScore ?? 0)
                $Acs = @($Latest.averageComparativeScores)
                $VsAll = ($Acs | Where-Object { $_.basis -eq 'AllTenants' } | Select-Object -First 1).averageScore
                $VsSim = ($Acs | Where-Object { $_.basis -eq 'TotalSeats' } | Select-Object -First 1).averageScore
                # Trend: the 7 most recent points, drawn oldest-first.
                $Trend = @($Scores | Select-Object -First 7 | Sort-Object -Property @{ Expression = { [datetime]$_.createdDateTime } } | ForEach-Object {
                        @{ label = ([datetime]$_.createdDateTime).ToString('MMM d'); value = [math]::Round([double]($_.currentScore ?? 0), 2) }
                    })
                $SecureScore = @{
                    currentScore           = [math]::Round($Cur, 2)
                    maxScore               = $Max
                    percentageCurrent      = $(if ($Max -gt 0) { [math]::Round(($Cur / $Max) * 100) } else { 0 })
                    percentageVsSimilar    = $(if ($null -ne $VsSim) { [math]::Round([double]$VsSim) } else { $null })
                    percentageVsAllTenants = $(if ($null -ne $VsAll) { [math]::Round([double]$VsAll) } else { $null })
                    trend                  = $Trend
                }
            }
        } catch { Write-Information "Executive report: secure score unavailable - $($_.Exception.Message)" }

        # -- Security standards (CippStandardsReports table + the standards catalog) --
        $SecurityControls = @()
        try {
            $StdTable = Get-CIPPTable -TableName 'CippStandardsReports'
            $StdRows = @(Get-CIPPAzDataTableEntity @StdTable -Filter "PartitionKey eq '$TenantFilter'")
            if ($StdRows.Count -gt 0) {
                $TenantStd = [ordered]@{ tenantFilter = $TenantFilter }
                foreach ($Row in $StdRows) {
                    $FieldName = [string]$Row.RowKey
                    # Quarantine template rows hex-encode the display name in the key; decode it as the page does.
                    if ($FieldName -match '^(standards\.QuarantineTemplate\.)([0-9a-fA-F]+)$') {
                        $Prefix = $Matches[1]; $Hex = $Matches[2]
                        $Chars = for ($i = 0; $i -lt $Hex.Length; $i += 2) { [char][Convert]::ToInt32($Hex.Substring($i, 2), 16) }
                        $FieldName = "$Prefix$(-join $Chars)"
                    }
                    $Cv = if (-not [string]::IsNullOrWhiteSpace([string]$Row.CurrentValue) -and (Test-Json -Json ([string]$Row.CurrentValue) -ErrorAction SilentlyContinue)) { $Row.CurrentValue | ConvertFrom-Json -ErrorAction SilentlyContinue } else { $Row.CurrentValue }
                    $Ev = if (-not [string]::IsNullOrWhiteSpace([string]$Row.ExpectedValue) -and (Test-Json -Json ([string]$Row.ExpectedValue) -ErrorAction SilentlyContinue)) { $Row.ExpectedValue | ConvertFrom-Json -ErrorAction SilentlyContinue } else { $Row.ExpectedValue }
                    $Val = $Row.Value
                    if ($Val -is [string] -and -not [string]::IsNullOrWhiteSpace($Val) -and (Test-Json -Json $Val -ErrorAction SilentlyContinue)) { $Val = $Val | ConvertFrom-Json -ErrorAction SilentlyContinue }
                    $TenantStd[$FieldName] = @{ Value = $Val; CurrentValue = $Cv; ExpectedValue = $Ev }
                }
                $Catalog = @()
                try {
                    $CatPath = Join-Path $env:CIPPRootPath 'Config\standards.json'
                    if (Test-Path $CatPath) { $Catalog = @(Get-Content $CatPath -Raw | ConvertFrom-Json -Depth 20) }
                } catch { $Catalog = @() }
                $SecurityControls = @(Convert-CippExecStandardsToControls -Compare @([pscustomobject]$TenantStd) -Catalog $Catalog)
            }
        } catch { Write-Information "Executive report: standards unavailable - $($_.Exception.Message)" }

        $Data = @{
            TenantName       = $TenantName
            UserStats        = $UserStats
            SecureScore      = $SecureScore
            Licenses         = $Licenses
            Devices          = $Devices
            CAPolicies       = $CAPolicies
            SecurityControls = $SecurityControls
        }

        # Optional per-section toggles from the client's section panel (POST body). Absent -> full report.
        $SectionConfig = @{}
        $RawCfg = $Request.Body.sectionConfig
        if ($RawCfg -is [hashtable]) { $SectionConfig = $RawCfg }
        elseif ($RawCfg) { foreach ($p in $RawCfg.PSObject.Properties) { $SectionConfig[$p.Name] = [bool]$p.Value } }

        $Report = Build-CippExecutiveReportTree -Data $Data -SectionConfig $SectionConfig

        # Branding: a named preset if the client selected one (the report's Branding dropdown), else
        # the tenant/global default.
        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName $TenantName -TenantFilter $TenantFilter `
            -ReportName 'Executive Summary' -BrandingPresetId $BrandingPresetId

        $FileName = ("Executive_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render Executive report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
