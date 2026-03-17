function Invoke-CIPPStandardNinjaCveSync {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) NinjaCveSync
    .SYNOPSIS
        (Label) Sync Defender CVEs to NinjaOne
    .DESCRIPTION
        (Helptext) Pulls Defender TVM vulnerabilities for each tenant and uploads them to a specified NinjaOne Scan Group.
        (DocsDescription) This standard queries Microsoft Defender Threat & Vulnerability Management (TVM) for all software vulnerabilities affecting devices in the tenant. Results are converted into a NinjaOne-compatible CSV and uploaded to the configured NinjaOne Scan Group.
    .NOTES
        CAT
            Global Standards
        TAG
            Security
        DISABLEDFEATURES
            {"report":true,"warn":true,"remediate":true}
        EXECUTIVETEXT
            Automatically synchronizes Microsoft Defender vulnerabilities into NinjaOne for unified alerting and remediation workflows, ensuring your RMM platform always reflects the real security posture of your clients.
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.NinjaCveSync.ScanGroupPrefix","label":"Scan Group Name Prefix (optional, e.g., 'CIPP-')","required":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-01-22
        RECOMMENDEDBY
            ["CIPP"]
        UPDATECOMMENTBLOCK
            Run Tools\Update-StandardsComments.ps1 after editing this header.
    #>
    param(
        $Tenant,
        $Settings
    )

    Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Starting Ninja CVE Sync standard" -Sev 'Info'

    # ============================
    # 1. BUILD SCAN GROUP NAME FROM TENANT
    # ============================
    # Use optional prefix + tenant domain for scan group name
    $Prefix = if ($Settings.ScanGroupPrefix) { $Settings.ScanGroupPrefix } else { "" }
    $ScanGroupName = "$Prefix$Tenant"
    
    Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Using scan group name: '$ScanGroupName' (prefix: '$Prefix', tenant: '$Tenant')" -Sev 'Info'

    # ============================
    # 2. GET NINJAONE CONFIGURATION
    # ============================
    try {
        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Retrieving NinjaOne configuration from Extensions table" -Sev 'Debug'
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $ConfigEntity = Get-AzDataTableEntity @Table
        
        if (-not $ConfigEntity -or -not $ConfigEntity.config) {
            throw "No configuration found in Extensionsconfig table"
        }
        
        $Configuration = ($ConfigEntity.config | ConvertFrom-Json).NinjaOne
        
        if (-not $Configuration -or -not $Configuration.Instance) {
            throw "NinjaOne configuration is missing or incomplete"
        }
        
        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Retrieved NinjaOne config for instance: $($Configuration.Instance)" -Sev 'Debug'
    }
    catch {
        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Failed to retrieve NinjaOne configuration: $($_.Exception.Message)" -Sev 'Error'
        throw "Failed to retrieve NinjaOne configuration: $($_.Exception.Message)"
    }

    try {
        # ============================
        # 3. QUERY DEFENDER TVM (using helper function)
        # ============================
        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Pulling Defender TVM data via Get-DefenderTvmRaw" -Sev 'Debug'
        
        $AllVulns = Get-DefenderTvmRaw -TenantId $Tenant -MaxPages 0
        
        if (-not $AllVulns) {
            Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "No vulnerability data returned from Defender TVM" -Sev 'Warning'
            $AllVulns = @()
        }

        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Retrieved $($AllVulns.Count) vulnerabilities from Defender TVM" -Sev 'Info'

        # ============================
        # 4. GET NINJA TOKEN WITH CONFIG
        # ============================
        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Retrieving NinjaOne API token" -Sev 'Debug'
        
        $Token = Get-NinjaOneToken -configuration $Configuration
        
        if (-not $Token -or -not $Token.access_token) {
            throw "Failed to retrieve NinjaOne access token"
        }
        
        $Headers = @{
            "Authorization" = "Bearer $($Token.access_token)"
        }
        
        # Build base API URL from configuration
        $NinjaBaseUrl = "https://$($Configuration.Instance)/api/v2"
        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Using NinjaOne API base: $NinjaBaseUrl" -Sev 'Debug'

        # ============================
        # 5. RESOLVE SCAN GROUP AND GET HEADERS
        # ============================
        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Resolving scan group '$ScanGroupName' and fetching CSV header configuration" -Sev 'Debug'
        
        $ScanGroupsUri = "$NinjaBaseUrl/vulnerability/scan-groups"
        
        try {
            $ScanGroups = Invoke-RestMethod -Method Get -Uri $ScanGroupsUri -Headers $Headers -TimeoutSec 30
        }
        catch {
            Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Failed to retrieve scan groups: $($_.Exception.Message)" -Sev 'Error'
            throw "Failed to retrieve scan groups from NinjaOne: $($_.Exception.Message)"
        }

        if (-not $ScanGroups) {
            throw "Failed to retrieve scan groups from NinjaOne. Response was empty."
        }

        # Look up the scan group by name to get its numeric ID
        $ResolvedScanGroup = $ScanGroups | Where-Object { $_.groupName -eq $ScanGroupName }

        if (-not $ResolvedScanGroup) {
            $Available = ($ScanGroups | Select-Object -First 10 | ForEach-Object { "ID $($_.id): $($_.groupName)" }) -join ', '
            Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Unable to resolve scan group '$ScanGroupName'. Available groups: $Available" -Sev 'Error'
            throw "Scan group '$ScanGroupName' not found. Available groups: $Available"
        }

        $ResolvedScanGroupId = $ResolvedScanGroup.id
        
        # Get the expected CSV headers from the scan group configuration
        $DeviceIdHeader = $ResolvedScanGroup.deviceIdHeader
        $CveIdHeader = $ResolvedScanGroup.cveIdHeader
        
        if ([string]::IsNullOrWhiteSpace($DeviceIdHeader) -or [string]::IsNullOrWhiteSpace($CveIdHeader)) {
            Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Scan group missing header config (deviceIdHeader: '$DeviceIdHeader', cveIdHeader: '$CveIdHeader')" -Sev 'Error'
            throw "Scan group is missing required header configuration"
        }
        
        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Resolved scan group '$ScanGroupName' to ID $ResolvedScanGroupId" -Sev 'Info'
        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "CSV headers - Device: '$DeviceIdHeader', CVE: '$CveIdHeader'" -Sev 'Info'

        # ============================
        # 6. TRANSFORM TO CSV ROWS
        # ============================
        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Transforming CVE data into Ninja CSV format" -Sev 'Debug'
        $CsvRows = @()
        $SkippedCount = 0

        foreach ($item in $AllVulns) {
            # Validate required fields
            if ([string]::IsNullOrWhiteSpace($item.cveId) -or [string]::IsNullOrWhiteSpace($item.deviceName)) {
                $SkippedCount++
                continue
            }
            
            # Use dynamic headers from scan group configuration
            $CsvRows += [PSCustomObject]@{
                $DeviceIdHeader = $item.deviceName.Trim()
                $CveIdHeader    = $item.cveId.Trim()
            }
        }

        if ($SkippedCount -gt 0) {
            Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Skipped $SkippedCount vulnerabilities due to missing deviceName or cveId" -Sev 'Warning'
        }

        if ($CsvRows.Count -eq 0) {
            Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "No valid CVEs found to upload for this tenant" -Sev 'Info'
            
            if ($Settings.report) {
                Set-CIPPStandardsCompareField -FieldName 'standards.NinjaCveSync' -FieldValue "No valid CVEs detected" -TenantFilter $Tenant
            }
            return
        }

        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Prepared $($CsvRows.Count) CVE rows for upload" -Sev 'Info'

        # ============================
        # 7. BUILD CSV BYTES (using helper function)
        # ============================
        $CsvBytes = New-VulnCsvBytes -Rows $CsvRows -Headers @($DeviceIdHeader, $CveIdHeader)
        
        if (-not $CsvBytes -or $CsvBytes.Length -eq 0) {
            throw "Failed to generate CSV bytes from vulnerability data"
        }
        
        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Generated CSV payload: $($CsvBytes.Length) bytes" -Sev 'Debug'

        # ============================
        # 8. UPLOAD TO NINJAONE (using helper function)
        # ============================
        # Use the numeric scan group ID in the URL
        $UploadUri = "$NinjaBaseUrl/vulnerability/scan-groups/$ResolvedScanGroupId/upload"
        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Uploading CVE CSV to NinjaOne (ScanGroup: '$ScanGroupName', ID: $ResolvedScanGroupId, Uri: $UploadUri)" -Sev 'Info'

        try {
            $Response = Invoke-NinjaOneVulnCsvUpload `
                -Uri $UploadUri `
                -CsvBytes $CsvBytes `
                -Headers $Headers
            
            Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Upload completed successfully" -Sev 'Info'
            
            # Log the full response received from upload helper
            if ($Response) {
                Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Response from upload helper: $($Response | ConvertTo-Json -Compress)" -Sev 'Debug'
            } else {
                Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "No response object returned from upload helper" -Sev 'Warning'
            }
            
            # Check if polling timed out
            if ($Response -and $Response.PollingTimedOut) {
                Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "WARNING: Status polling timed out. Upload may still succeed - check NinjaOne UI to confirm." -Sev 'Warning'
            }
            
            # Log processing results if available
            if ($Response -and $Response.recordsProcessed) {
                $SentCount = $CsvRows.Count
                $ProcessedCount = $Response.recordsProcessed
                
                if ($ProcessedCount -lt $SentCount) {
                    $SkippedCount = $SentCount - $ProcessedCount
                    Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "NinjaOne processed $ProcessedCount of $SentCount rows ($SkippedCount skipped/deduplicated)" -Sev 'Info'
                } else {
                    Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "NinjaOne processed all $ProcessedCount rows" -Sev 'Info'
                }
            } else {
                Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "No recordsProcessed count in response - cannot verify processing" -Sev 'Warning'
            }
        }
        catch {
            # Error already logged by helper function
            throw
        }

        # ============================
        # 9. REPORT MODE
        # ============================
        if ($Settings.report) {
            $ReportMessage = "Uploaded $($CsvRows.Count) CVEs to scan group '$ScanGroupName' (ID: $ResolvedScanGroupId)"
            Set-CIPPStandardsCompareField -FieldName "standards.NinjaCveSync" -FieldValue $ReportMessage -TenantFilter $Tenant
        }

        # ============================
        # 10. ALERT MODE
        # ============================
        if ($Settings.alert) {
            Write-StandardsAlert -message "Uploaded $($CsvRows.Count) CVEs to NinjaOne scan group '$ScanGroupName' (ID: $ResolvedScanGroupId)" -tenant $Tenant -standardName 'NinjaCveSync' -standardId $Settings.standardId
        }

        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Ninja CVE Sync completed successfully for $($CsvRows.Count) CVEs" -Sev 'Info'

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'NinjaCveSync' -tenant $Tenant -message "Ninja CVE Sync failed: $ErrorMessage" -Sev 'Error'
        
        if ($Settings.report) {
            Set-CIPPStandardsCompareField -FieldName "standards.NinjaCveSync" -FieldValue "Failed: $ErrorMessage" -TenantFilter $Tenant
        }
        
        throw $ErrorMessage
    }
}