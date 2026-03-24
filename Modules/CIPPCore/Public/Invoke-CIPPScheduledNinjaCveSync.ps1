function Invoke-CIPPScheduledNinjaCveSync {
    <#
    .SYNOPSIS
        Scheduled task: Sync Defender CVEs to NinjaOne for a single tenant
    .DESCRIPTION
        Called by the CIPP scheduler once per tenant. TenantFilter and ScanGroupPrefix
        are passed in via the task Parameters object when the task is registered via
        Register-CIPPExtensionScheduledTasks. Reads NinjaOne credentials from
        Extensionsconfig, pulls Defender TVM vulnerabilities, filters CIPP exceptions,
        and uploads a CSV to the configured NinjaOne scan group.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [Parameter()][string]$ScanGroupPrefix = ''
    )

    $ScanGroupName = "$ScanGroupPrefix$TenantFilter"
    Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Starting NinjaCveSync — scan group: '$ScanGroupName'" -Sev 'Info'

    # ============================
    # 1. LOAD NINJAONE CREDENTIALS FROM Extensionsconfig
    # ============================
    try {
        $ExtTable     = Get-CIPPTable -TableName 'Extensionsconfig'
        $ConfigEntity = Get-CIPPAzDataTableEntity @ExtTable

        if (-not $ConfigEntity -or -not $ConfigEntity.config) {
            throw "No configuration found in Extensionsconfig table"
        }

        $Configuration = ($ConfigEntity.config | ConvertFrom-Json).NinjaOne

        if (-not $Configuration -or -not $Configuration.Instance) {
            throw "NinjaOne configuration is missing or incomplete in Extensionsconfig"
        }
    }
    catch {
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Failed to retrieve NinjaOne configuration: $($_.Exception.Message)" -Sev 'Error'
        throw
    }

    try {
        # ============================
        # 2. PULL DEFENDER TVM DATA
        # ============================
        $AllVulns = Get-DefenderTvmRaw -TenantId $TenantFilter -MaxPages 0

        if (-not $AllVulns) {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "No vulnerability data returned from Defender TVM" -Sev 'Warning'
            $AllVulns = @()
        }

        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Retrieved $($AllVulns.Count) vulnerabilities from Defender TVM" -Sev 'Info'

        # ============================
        # 3. FILTER CIPP EXCEPTIONS
        # ============================
        $ExceptionsTable     = Get-CIPPTable -TableName 'CveExceptions'
        $AllExceptions       = Get-CIPPAzDataTableEntity @ExceptionsTable
        $ApplicableExceptions = $AllExceptions | Where-Object { $_.RowKey -eq $TenantFilter -or $_.RowKey -eq 'ALL' }

        if ($ApplicableExceptions) {
            $ExceptedCveIds = $ApplicableExceptions | Select-Object -ExpandProperty cveId -Unique
            $BeforeCount    = $AllVulns.Count
            $AllVulns       = $AllVulns | Where-Object { $_.cveId -notin $ExceptedCveIds }
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Filtered $($BeforeCount - $AllVulns.Count) excepted CVEs — $($AllVulns.Count) remaining" -Sev 'Info'
        }

        # ============================
        # 4. GET NINJAONE TOKEN
        # ============================
        $Token = Get-NinjaOneToken -configuration $Configuration

        if (-not $Token -or -not $Token.access_token) {
            throw "Failed to retrieve NinjaOne access token"
        }

        $Headers      = @{ 'Authorization' = "Bearer $($Token.access_token)" }
        $NinjaBaseUrl = "https://$($Configuration.Instance)/api/v2"

        # ============================
        # 5. RESOLVE SCAN GROUP
        # ============================
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
        $DeviceIdHeader      = $ResolvedScanGroup.deviceIdHeader
        $CveIdHeader         = $ResolvedScanGroup.cveIdHeader

        if ([string]::IsNullOrWhiteSpace($DeviceIdHeader) -or [string]::IsNullOrWhiteSpace($CveIdHeader)) {
            throw "Scan group missing required header config (deviceIdHeader: '$DeviceIdHeader', cveIdHeader: '$CveIdHeader')"
        }

        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Scan group '$ScanGroupName' resolved (ID: $ResolvedScanGroupId)" -Sev 'Debug'

        # ============================
        # 6. BUILD CSV ROWS
        # ============================
        $CsvRows      = @()
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

        # ============================
        # 7. BUILD CSV BYTES
        # ============================
        $CsvBytes = New-VulnCsvBytes -Rows $CsvRows -Headers @($DeviceIdHeader, $CveIdHeader)

        if (-not $CsvBytes -or $CsvBytes.Length -eq 0) {
            throw "Failed to generate CSV bytes"
        }

        # ============================
        # 8. UPLOAD TO NINJAONE
        # ============================
        $UploadUri = "$NinjaBaseUrl/vulnerability/scan-groups/$ResolvedScanGroupId/upload"
        $Response  = Invoke-NinjaOneVulnCsvUpload -Uri $UploadUri -CsvBytes $CsvBytes -Headers $Headers

        if ($Response -and $Response.PollingTimedOut) {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Status polling timed out — check NinjaOne UI to confirm upload" -Sev 'Warning'
        }

        $ProcessedCount = if ($Response -and $Response.recordsProcessed) { $Response.recordsProcessed } else { '?' }
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "NinjaCveSync complete — $($CsvRows.Count) CVEs sent to '$ScanGroupName', $ProcessedCount processed by NinjaOne" -Sev 'Info'

    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "NinjaCveSync failed: $ErrorMessage" -Sev 'Error'
        throw $ErrorMessage
    }
}
