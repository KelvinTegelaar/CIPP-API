function Invoke-CIPPScheduledNinjaCveSync {
    <#
    .SYNOPSIS
        Scheduled task: Sync Defender CVEs to NinjaOne for a single tenant
    .DESCRIPTION
        Called by the CIPP scheduler once per tenant. TenantFilter and ScanGroupPrefix
        are passed in via the task Parameters object when the task is registered via
        the CippNinjaCveSyncScheduleDrawer. Reads NinjaOne credentials from
        Extensionsconfig, pulls Defender TVM vulnerabilities, filters CIPP exceptions,
        and uploads a CSV to the configured NinjaOne scan group.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [Parameter()][string]$ScanGroupPrefix = ''
    )

    Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Starting scheduled NinjaCveSync" -Sev 'Info'

    # ============================
    # 1. BUILD SCAN GROUP NAME
    # ============================
    $ScanGroupName = "$ScanGroupPrefix$TenantFilter"
    Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Scan group name: '$ScanGroupName'" -Sev 'Info'

    # ============================
    # 2. LOAD NINJAONE CREDENTIALS FROM Extensionsconfig
    # ============================
    try {
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Retrieving NinjaOne credentials from Extensionsconfig" -Sev 'Debug'
        $ExtTable = Get-CIPPTable -TableName 'Extensionsconfig'
        $ConfigEntity = Get-CIPPAzDataTableEntity @ExtTable

        if (-not $ConfigEntity -or -not $ConfigEntity.config) {
            throw "No configuration found in Extensionsconfig table"
        }

        $Configuration = ($ConfigEntity.config | ConvertFrom-Json).NinjaOne

        if (-not $Configuration -or -not $Configuration.Instance) {
            throw "NinjaOne configuration is missing or incomplete in Extensionsconfig"
        }

        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "NinjaOne instance: $($Configuration.Instance)" -Sev 'Debug'
    }
    catch {
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Failed to retrieve NinjaOne configuration: $($_.Exception.Message)" -Sev 'Error'
        throw
    }

    try {
        # ============================
        # 3. PULL DEFENDER TVM DATA
        # ============================
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Pulling Defender TVM data" -Sev 'Debug'
        $AllVulns = Get-DefenderTvmRaw -TenantId $TenantFilter -MaxPages 0

        if (-not $AllVulns) {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "No vulnerability data returned from Defender TVM" -Sev 'Warning'
            $AllVulns = @()
        }

        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Retrieved $($AllVulns.Count) vulnerabilities" -Sev 'Info'

        # ============================
        # 4. FILTER CIPP EXCEPTIONS
        # ============================
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Checking CVE exceptions" -Sev 'Debug'
        $ExceptionsTable = Get-CIPPTable -TableName 'CveExceptions'
        $AllExceptions = Get-CIPPAzDataTableEntity @ExceptionsTable
        $ApplicableExceptions = $AllExceptions | Where-Object { $_.RowKey -eq $TenantFilter -or $_.RowKey -eq 'ALL' }

        if ($ApplicableExceptions) {
            $ExceptedCveIds = $ApplicableExceptions | Select-Object -ExpandProperty cveId -Unique
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Found $($ExceptedCveIds.Count) excepted CVE(s)" -Sev 'Info'
            $BeforeCount = $AllVulns.Count
            $AllVulns = $AllVulns | Where-Object { $_.cveId -notin $ExceptedCveIds }
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Filtered out $($BeforeCount - $AllVulns.Count) CVE entries (remaining: $($AllVulns.Count))" -Sev 'Info'
        }
        else {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "No CVE exceptions found for this tenant" -Sev 'Debug'
        }

        # ============================
        # 5. GET NINJAONE TOKEN
        # ============================
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Retrieving NinjaOne API token" -Sev 'Debug'
        $Token = Get-NinjaOneToken -configuration $Configuration

        if (-not $Token -or -not $Token.access_token) {
            throw "Failed to retrieve NinjaOne access token"
        }

        $Headers = @{ 'Authorization' = "Bearer $($Token.access_token)" }
        $NinjaBaseUrl = "https://$($Configuration.Instance)/api/v2"

        # ============================
        # 6. RESOLVE SCAN GROUP
        # ============================
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Resolving scan group '$ScanGroupName'" -Sev 'Debug'

        try {
            $ScanGroups = Invoke-RestMethod -Method Get -Uri "$NinjaBaseUrl/vulnerability/scan-groups" -Headers $Headers -TimeoutSec 30
        }
        catch {
            throw "Failed to retrieve scan groups from NinjaOne: $($_.Exception.Message)"
        }

        if (-not $ScanGroups) {
            throw "Scan groups response was empty"
        }

        $ResolvedScanGroup = $ScanGroups | Where-Object { $_.groupName -eq $ScanGroupName }

        if (-not $ResolvedScanGroup) {
            $Available = ($ScanGroups | Select-Object -First 10 | ForEach-Object { "ID $($_.id): $($_.groupName)" }) -join ', '
            throw "Scan group '$ScanGroupName' not found. Available: $Available"
        }

        $ResolvedScanGroupId = $ResolvedScanGroup.id
        $DeviceIdHeader = $ResolvedScanGroup.deviceIdHeader
        $CveIdHeader    = $ResolvedScanGroup.cveIdHeader

        if ([string]::IsNullOrWhiteSpace($DeviceIdHeader) -or [string]::IsNullOrWhiteSpace($CveIdHeader)) {
            throw "Scan group missing required header config (deviceIdHeader: '$DeviceIdHeader', cveIdHeader: '$CveIdHeader')"
        }

        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Scan group resolved — ID: $ResolvedScanGroupId, Headers: '$DeviceIdHeader' / '$CveIdHeader'" -Sev 'Info'

        # ============================
        # 7. BUILD CSV ROWS
        # ============================
        $CsvRows = @()
        $SkippedCount = 0

        foreach ($item in $AllVulns) {
            if ([string]::IsNullOrWhiteSpace($item.cveId) -or [string]::IsNullOrWhiteSpace($item.deviceName)) {
                $SkippedCount++
                continue
            }
            $CsvRows += [PSCustomObject]@{
                $DeviceIdHeader = $item.deviceName.Trim()
                $CveIdHeader    = $item.cveId.Trim()
            }
        }

        if ($SkippedCount -gt 0) {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Skipped $SkippedCount rows (missing deviceName or cveId)" -Sev 'Warning'
        }

        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Prepared $($CsvRows.Count) CSV rows for upload" -Sev 'Info'

        # ============================
        # 8. BUILD CSV BYTES
        # ============================
        $CsvBytes = New-VulnCsvBytes -Rows $CsvRows -Headers @($DeviceIdHeader, $CveIdHeader)

        if (-not $CsvBytes -or $CsvBytes.Length -eq 0) {
            throw "Failed to generate CSV bytes"
        }

        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "CSV payload: $($CsvBytes.Length) bytes" -Sev 'Debug'

        # ============================
        # 9. UPLOAD TO NINJAONE
        # ============================
        $UploadUri = "$NinjaBaseUrl/vulnerability/scan-groups/$ResolvedScanGroupId/upload"
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Uploading to NinjaOne (group: '$ScanGroupName', ID: $ResolvedScanGroupId)" -Sev 'Info'

        $Response = Invoke-NinjaOneVulnCsvUpload -Uri $UploadUri -CsvBytes $CsvBytes -Headers $Headers

        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Upload completed successfully" -Sev 'Info'

        if ($Response -and $Response.PollingTimedOut) {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Status polling timed out — check NinjaOne UI to confirm" -Sev 'Warning'
        }

        if ($Response -and $Response.recordsProcessed) {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "NinjaOne processed $($Response.recordsProcessed) of $($CsvRows.Count) rows" -Sev 'Info'
        }

        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "NinjaCveSync complete — $($CsvRows.Count) CVEs uploaded to '$ScanGroupName'" -Sev 'Info'

    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "NinjaCveSync failed: $ErrorMessage" -Sev 'Error'
        throw $ErrorMessage
    }
}
