function Invoke-CIPPScheduledNinjaCveSync {
    <#
    .SYNOPSIS
        Scheduled task: Sync Defender CVEs to NinjaOne for all mapped tenants
    .DESCRIPTION
        Runs as a single scheduled task (not per-tenant). Loops all tenants mapped
        in NinjaOne sequentially, pulling Defender TVM vulnerabilities, filtering
        CIPP exceptions, and uploading a CSV to each tenant's NinjaOne scan group.
        ScanGroupPrefix is read from Extensionsconfig (NinjaOne.CveSyncPrefix).
        Sequential execution ensures NinjaOne is not overwhelmed by simultaneous uploads.
    #>
    [CmdletBinding()]
    param()

    Write-LogMessage -API 'NinjaCveSync' -message "Starting NinjaCveSync for all mapped tenants" -Sev 'Info'

    # ============================
    # 1. LOAD NINJAONE CONFIG
    # ============================
    try {
        $ExtTable     = Get-CIPPTable -TableName 'Extensionsconfig'
        $ConfigEntity = Get-CIPPAzDataTableEntity @ExtTable

        if (-not $ConfigEntity -or -not $ConfigEntity.config) {
            throw "No configuration found in Extensionsconfig table"
        }

        $NinjaConfig = ($ConfigEntity.config | ConvertFrom-Json).NinjaOne

        if (-not $NinjaConfig -or -not $NinjaConfig.Instance) {
            throw "NinjaOne configuration is missing or incomplete"
        }

        $ScanGroupPrefix = if ($NinjaConfig.CveSyncPrefix) { $NinjaConfig.CveSyncPrefix } else { '' }

        Write-LogMessage -API 'NinjaCveSync' -message "NinjaOne instance: $($NinjaConfig.Instance), prefix: '$ScanGroupPrefix'" -Sev 'Debug'
    }
    catch {
        Write-LogMessage -API 'NinjaCveSync' -message "Failed to load NinjaOne configuration: $($_.Exception.Message)" -Sev 'Error'
        throw
    }

    # ============================
    # 2. GET NINJAONE TOKEN
    # ============================
    try {
        $Token = Get-NinjaOneToken -configuration $NinjaConfig

        if (-not $Token -or -not $Token.access_token) {
            throw "Failed to retrieve NinjaOne access token"
        }

        $Headers      = @{ 'Authorization' = "Bearer $($Token.access_token)" }
        $NinjaBaseUrl = "https://$($NinjaConfig.Instance)/api/v2"
    }
    catch {
        Write-LogMessage -API 'NinjaCveSync' -message "Failed to retrieve NinjaOne token: $($_.Exception.Message)" -Sev 'Error'
        throw
    }

    # ============================
    # 3. GET SCAN GROUPS ONCE (shared across all tenants)
    # ============================
    try {
        $ScanGroups = Invoke-RestMethod -Method Get -Uri "$NinjaBaseUrl/vulnerability/scan-groups" -Headers $Headers -TimeoutSec 30

        if (-not $ScanGroups) {
            throw "Scan groups response was empty"
        }

        Write-LogMessage -API 'NinjaCveSync' -message "Retrieved $($ScanGroups.Count) scan groups from NinjaOne" -Sev 'Debug'
    }
    catch {
        Write-LogMessage -API 'NinjaCveSync' -message "Failed to retrieve scan groups: $($_.Exception.Message)" -Sev 'Error'
        throw
    }

    # ============================
    # 4. GET CIPP EXCEPTIONS (all tenants, loaded once)
    # ============================
    $ExceptionsTable = Get-CIPPTable -TableName 'CveExceptions'
    $AllExceptions   = Get-CIPPAzDataTableEntity @ExceptionsTable

    # ============================
    # 5. GET MAPPED TENANTS
    # ============================
    $MappingsTable = Get-CIPPTable -TableName 'CippMapping'
    $Mappings      = Get-CIPPAzDataTableEntity @MappingsTable -Filter "PartitionKey eq 'NinjaOneMapping'"
    $Tenants       = Get-Tenants -IncludeErrors

    if (-not $Mappings) {
        Write-LogMessage -API 'NinjaCveSync' -message "No tenants mapped in NinjaOne — nothing to sync" -Sev 'Warning'
        return
    }

    Write-LogMessage -API 'NinjaCveSync' -message "Processing $($Mappings.Count) mapped tenant(s)" -Sev 'Info'

    $SuccessCount = 0
    $FailCount    = 0

    # ============================
    # 6. LOOP TENANTS SEQUENTIALLY
    # ============================
    foreach ($Mapping in $Mappings) {
        $Tenant = $Tenants | Where-Object { $_.customerId -eq $Mapping.RowKey }

        if (-not $Tenant) {
            Write-LogMessage -API 'NinjaCveSync' -message "Tenant $($Mapping.RowKey) not found in tenant list — skipping" -Sev 'Warning'
            continue
        }

        $TenantFilter  = $Tenant.defaultDomainName
        $ScanGroupName = "$ScanGroupPrefix$TenantFilter"

        try {
            # ============================
            # 6a. PULL DEFENDER TVM DATA
            # ============================
            $AllVulns = Get-DefenderTvmRaw -TenantId $TenantFilter -MaxPages 0

            if (-not $AllVulns) {
                Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "No vulnerability data returned — skipping" -Sev 'Warning'
                continue
            }

            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Retrieved $($AllVulns.Count) vulnerabilities" -Sev 'Info'

            # ============================
            # 6b. FILTER CIPP EXCEPTIONS
            # ============================
            $ApplicableExceptions = $AllExceptions | Where-Object { $_.RowKey -eq $TenantFilter -or $_.RowKey -eq 'ALL' }

            if ($ApplicableExceptions) {
                $ExceptedCveIds = $ApplicableExceptions | Select-Object -ExpandProperty cveId -Unique
                $BeforeCount    = $AllVulns.Count
                $AllVulns       = $AllVulns | Where-Object { $_.cveId -notin $ExceptedCveIds }
                Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Filtered $($BeforeCount - $AllVulns.Count) excepted CVEs — $($AllVulns.Count) remaining" -Sev 'Info'
            }

            # ============================
            # 6c. RESOLVE SCAN GROUP
            # ============================
            $ResolvedScanGroup = $ScanGroups | Where-Object { $_.groupName -eq $ScanGroupName }

            if (-not $ResolvedScanGroup) {
                $Available = ($ScanGroups | Select-Object -First 10 | ForEach-Object { "ID $($_.id): $($_.groupName)" }) -join ', '
                throw "Scan group '$ScanGroupName' not found. Available: $Available"
            }

            $ResolvedScanGroupId = $ResolvedScanGroup.id
            $DeviceIdHeader      = $ResolvedScanGroup.deviceIdHeader
            $CveIdHeader         = $ResolvedScanGroup.cveIdHeader

            if ([string]::IsNullOrWhiteSpace($DeviceIdHeader) -or [string]::IsNullOrWhiteSpace($CveIdHeader)) {
                throw "Scan group missing required header config"
            }

            # ============================
            # 6d. BUILD AND UPLOAD CSV
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

            $CsvBytes = New-VulnCsvBytes -Rows $CsvRows -Headers @($DeviceIdHeader, $CveIdHeader)

            if (-not $CsvBytes -or $CsvBytes.Length -eq 0) {
                throw "Failed to generate CSV bytes"
            }

            $UploadUri = "$NinjaBaseUrl/vulnerability/scan-groups/$ResolvedScanGroupId/upload"
            $Response  = Invoke-NinjaOneVulnCsvUpload -Uri $UploadUri -CsvBytes $CsvBytes -Headers $Headers

            if ($Response -and $Response.PollingTimedOut) {
                Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Status polling timed out — check NinjaOne UI to confirm" -Sev 'Warning'
            }

            $ProcessedCount = if ($Response -and $Response.recordsProcessed) { $Response.recordsProcessed } else { '?' }
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Complete — $($CsvRows.Count) CVEs sent to '$ScanGroupName', $ProcessedCount processed by NinjaOne" -Sev 'Info'

            $SuccessCount++
        }
        catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Failed: $ErrorMessage" -Sev 'Error'
            $FailCount++
            # Continue with next tenant rather than aborting the entire run
        }
    }

    Write-LogMessage -API 'NinjaCveSync' -message "NinjaCveSync complete — $SuccessCount succeeded, $FailCount failed" -Sev 'Info'
}
