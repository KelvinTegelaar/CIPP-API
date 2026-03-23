function Invoke-CIPPScheduledNinjaCveSync {
    <#
    .FUNCTIONALITY
        Entrypoint
    .COMPONENT
        (APIName) NinjaCveSync
    .SYNOPSIS
        (Label) Sync Defender CVEs to NinjaOne
    .DESCRIPTION
        (Helptext) Uploads Defender TVM vulnerabilities to NinjaOne scan groups for unified vulnerability tracking.
        (DocsDescription) This scheduled task pulls Microsoft Defender TVM vulnerability data for the tenant and uploads it to the corresponding NinjaOne scan group. Scan groups are matched by name using the configured prefix + tenant domain.
    .NOTES
        CAT
            Scheduled Tasks
        TAG
            Security, Integration
        IMPACT
            Low Impact
        ADDEDDATE
            2026-03-24
        RECOMMENDEDBY
            ["CIPP"]
    #>
    param(
        $Tenant
    )
    
    $APIName = 'ScheduledNinjaCveSync'
    
    Write-LogMessage -API $APIName -tenant $Tenant -message "Starting NinjaOne CVE sync for tenant" -Sev 'Info'
    
    try {
        # ============================
        # 1. GET NINJAONE CONFIGURATION
        # ============================
        Write-LogMessage -API $APIName -tenant $Tenant -message "Retrieving NinjaOne configuration" -Sev 'Debug'
        
        $ConfigTable = Get-CIPPTable -TableName 'Extensionsconfig'
        $ConfigEntity = Get-CIPPAzDataTableEntity @ConfigTable
        
        if (-not $ConfigEntity -or -not $ConfigEntity.config) {
            throw "No NinjaOne configuration found"
        }
        
        $Configuration = ($ConfigEntity.config | ConvertFrom-Json).NinjaOne
        
        if (-not $Configuration -or -not $Configuration.Instance) {
            throw "NinjaOne configuration is incomplete"
        }
        
        # ============================
        # 2. GET SCAN GROUP PREFIX FROM TASK PARAMETERS
        # ============================
        # Task parameters are passed when the scheduled task is created
        # For now, check if there's a NinjaCveSync config in Extensionsconfig
        $NinjaCveSyncConfig = ($ConfigEntity.config | ConvertFrom-Json).NinjaCveSync
        $ScanGroupPrefix = if ($NinjaCveSyncConfig.ScanGroupPrefix) { $NinjaCveSyncConfig.ScanGroupPrefix } else { "" }
        
        $ScanGroupName = "$ScanGroupPrefix$Tenant"
        
        Write-LogMessage -API $APIName -tenant $Tenant -message "Using scan group name: '$ScanGroupName'" -Sev 'Info'
        
        # ============================
        # 3. QUERY DEFENDER TVM
        # ============================
        Write-LogMessage -API $APIName -tenant $Tenant -message "Pulling Defender TVM data" -Sev 'Debug'
        
        $AllVulns = Get-DefenderTvmRaw -TenantId $Tenant -MaxPages 0
        
        if (-not $AllVulns) {
            $AllVulns = @()
        }
        
        Write-LogMessage -API $APIName -tenant $Tenant -message "Retrieved $($AllVulns.Count) vulnerabilities from Defender TVM" -Sev 'Info'
        
        # ============================
        # 4. GET NINJAONE TOKEN
        # ============================
        $Token = Get-NinjaOneToken -configuration $Configuration
        
        if (-not $Token -or -not $Token.access_token) {
            throw "Failed to retrieve NinjaOne access token"
        }
        
        $Headers = @{
            "Authorization" = "Bearer $($Token.access_token)"
        }
        
        $NinjaBaseUrl = "https://$($Configuration.Instance)/api/v2"
        
        # ============================
        # 5. RESOLVE SCAN GROUP
        # ============================
        Write-LogMessage -API $APIName -tenant $Tenant -message "Resolving scan group '$ScanGroupName'" -Sev 'Debug'
        
        $ScanGroupsUri = "$NinjaBaseUrl/vulnerability/scan-groups"
        
        try {
            $ScanGroups = Invoke-RestMethod -Method Get -Uri $ScanGroupsUri -Headers $Headers -TimeoutSec 30
        } catch {
            throw "Failed to retrieve scan groups from NinjaOne: $($_.Exception.Message)"
        }
        
        $ResolvedScanGroup = $ScanGroups | Where-Object { $_.groupName -eq $ScanGroupName }
        
        if (-not $ResolvedScanGroup) {
            Write-LogMessage -API $APIName -tenant $Tenant -message "Scan group '$ScanGroupName' not found in NinjaOne - skipping tenant" -Sev 'Warning'
            return
        }
        
        $ResolvedScanGroupId = $ResolvedScanGroup.id
        $DeviceIdHeader = $ResolvedScanGroup.deviceIdHeader
        $CveIdHeader = $ResolvedScanGroup.cveIdHeader
        
        if ([string]::IsNullOrWhiteSpace($DeviceIdHeader) -or [string]::IsNullOrWhiteSpace($CveIdHeader)) {
            throw "Scan group missing required header configuration"
        }
        
        Write-LogMessage -API $APIName -tenant $Tenant -message "Resolved scan group to ID $ResolvedScanGroupId" -Sev 'Info'
        
        # ============================
        # 6. TRANSFORM TO CSV ROWS
        # ============================
        Write-LogMessage -API $APIName -tenant $Tenant -message "Transforming CVE data into CSV format" -Sev 'Debug'
        
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
            Write-LogMessage -API $APIName -tenant $Tenant -message "Skipped $SkippedCount vulnerabilities due to missing data" -Sev 'Debug'
        }
        
        # Log appropriate message for 0 CVEs
        if ($CsvRows.Count -eq 0) {
            Write-LogMessage -API $APIName -tenant $Tenant -message "No CVEs found - uploading empty CSV to clear old data from NinjaOne" -Sev 'Info'
        } else {
            Write-LogMessage -API $APIName -tenant $Tenant -message "Prepared $($CsvRows.Count) CVE rows for upload" -Sev 'Info'
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
        
        Write-LogMessage -API $APIName -tenant $Tenant -message "Uploading CVE CSV to NinjaOne (ScanGroup: '$ScanGroupName', ID: $ResolvedScanGroupId)" -Sev 'Info'
        
        $Response = Invoke-NinjaOneVulnCsvUpload `
            -Uri $UploadUri `
            -CsvBytes $CsvBytes `
            -Headers $Headers
        
        # ============================
        # 9. LOG RESULTS
        # ============================
        if ($CsvRows.Count -eq 0) {
            Write-LogMessage -API $APIName -tenant $Tenant -message "No CVEs detected - cleared NinjaOne scan group" -Sev 'Info'
        } else {
            $ProcessedCount = if ($Response.recordsProcessed) { $Response.recordsProcessed } else { $CsvRows.Count }
            
            if ($ProcessedCount -lt $CsvRows.Count) {
                $SkippedByNinja = $CsvRows.Count - $ProcessedCount
                Write-LogMessage -API $APIName -tenant $Tenant -message "NinjaOne processed $ProcessedCount of $($CsvRows.Count) rows ($SkippedByNinja skipped/deduplicated)" -Sev 'Info'
            } else {
                Write-LogMessage -API $APIName -tenant $Tenant -message "Successfully uploaded $($CsvRows.Count) CVEs to NinjaOne" -Sev 'Info'
            }
        }
        
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API $APIName -tenant $Tenant -message "NinjaOne CVE sync failed: $ErrorMessage" -Sev 'Error'
        throw $ErrorMessage
    }
}
