function Invoke-CIPPStandardNinjaCveSync {
    <#
    .FUNCTIONALITY
        Entrypoint
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
        $TenantFilter,
        $Settings
    )

    Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Starting Ninja CVE Sync standard" -Sev 'Info'

    # ============================
    # 1. BUILD SCAN GROUP NAME FROM TENANT
    # ============================
    # Use optional prefix + tenant domain for scan group name
    $Prefix = if ($Settings.ScanGroupPrefix) { $Settings.ScanGroupPrefix } else { "" }
    $ScanGroupName = "$Prefix$TenantFilter"
    
    Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Using scan group name: '$ScanGroupName' (prefix: '$Prefix', tenant: '$TenantFilter')" -Sev 'Info'

    # ============================
    # 2. GET NINJAONE CONFIGURATION
    # ============================
    try {
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Retrieving NinjaOne configuration from Extensions table" -Sev 'Debug'
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $ConfigEntity = Get-AzDataTableEntity @Table
        
        if (-not $ConfigEntity -or -not $ConfigEntity.config) {
            throw "No configuration found in Extensionsconfig table"
        }
        
        $Configuration = ($ConfigEntity.config | ConvertFrom-Json).NinjaOne
        
        if (-not $Configuration -or -not $Configuration.Instance) {
            throw "NinjaOne configuration is missing or incomplete"
        }
        
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Retrieved NinjaOne config for instance: $($Configuration.Instance)" -Sev 'Debug'
    }
    catch {
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Failed to retrieve NinjaOne configuration: $($_.Exception.Message)" -Sev 'Error'
        throw "Failed to retrieve NinjaOne configuration: $($_.Exception.Message)"
    }

    try {
        # ============================
        # 3. READ CVE DATA FROM CACHE TABLE
        # ============================
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Reading CVE data from cache table" -Sev 'Debug'
        
        try {
            $CveCacheTable = Get-CIPPTable -TableName 'CveCache'
            
            # Get all CVEs for this tenant that are NOT excepted
            $Filter = "customerId eq '$TenantFilter' and hasException eq false"
            $AllVulns = Get-CIPPAzDataTableEntity @CveCacheTable -Filter $Filter
            
            if (-not $AllVulns) {
                Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "No non-excepted CVE data found in cache for this tenant" -Sev 'Warning'
                $AllVulns = @()
            }

            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Retrieved $($AllVulns.Count) non-excepted vulnerabilities from cache" -Sev 'Info'
        }
        catch {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Failed to read from CVE cache: $($_.Exception.Message)" -Sev 'Error'
            throw "Failed to read from CVE cache: $($_.Exception.Message)"
        }

        # ============================
        # 4. GET NINJA TOKEN WITH CONFIG
        # ============================
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Retrieving NinjaOne API token" -Sev 'Debug'
        
        $Token = Get-NinjaOneToken -configuration $Configuration
        
        if (-not $Token -or -not $Token.access_token) {
            throw "Failed to retrieve NinjaOne access token"
        }
        
        $Headers = @{
            "Authorization" = "Bearer $($Token.access_token)"
        }
        
        # Build base API URL from configuration
        $NinjaBaseUrl = "https://$($Configuration.Instance)/api/v2"
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Using NinjaOne API base: $NinjaBaseUrl" -Sev 'Debug'

        # ============================
        # 5. RESOLVE SCAN GROUP AND GET HEADERS
        # ============================
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Resolving scan group '$ScanGroupName' and fetching CSV header configuration" -Sev 'Debug'
        
        $ScanGroupsUri = "$NinjaBaseUrl/vulnerability/scan-groups"
        
        try {
            $ScanGroups = Invoke-RestMethod -Method Get -Uri $ScanGroupsUri -Headers $Headers -TimeoutSec 30
        }
        catch {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Failed to retrieve scan groups: $($_.Exception.Message)" -Sev 'Error'
            throw "Failed to retrieve scan groups from NinjaOne: $($_.Exception.Message)"
        }

        if (-not $ScanGroups) {
            throw "Failed to retrieve scan groups from NinjaOne. Response was empty."
        }

        # Look up the scan group by name to get its numeric ID
        $ResolvedScanGroup = $ScanGroups | Where-Object { $_.groupName -eq $ScanGroupName }

        if (-not $ResolvedScanGroup) {
            $Available = ($ScanGroups | Select-Object -First 10 | ForEach-Object { "ID $($_.id): $($_.groupName)" }) -join ', '
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Unable to resolve scan group '$ScanGroupName'. Available groups: $Available" -Sev 'Error'
            throw "Scan group '$ScanGroupName' not found. Available groups: $Available"
        }

        $ResolvedScanGroupId = $ResolvedScanGroup.id
        
        # Get the expected CSV headers from the scan group configuration
        $DeviceIdHeader = $ResolvedScanGroup.deviceIdHeader
        $CveIdHeader = $ResolvedScanGroup.cveIdHeader
        
        if ([string]::IsNullOrWhiteSpace($DeviceIdHeader) -or [string]::IsNullOrWhiteSpace($CveIdHeader)) {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Scan group missing header config (deviceIdHeader: '$DeviceIdHeader', cveIdHeader: '$CveIdHeader')" -Sev 'Error'
            throw "Scan group is missing required header configuration"
        }
        
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Resolved scan group '$ScanGroupName' to ID $ResolvedScanGroupId" -Sev 'Info'
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "CSV headers - Device: '$DeviceIdHeader', CVE: '$CveIdHeader'" -Sev 'Info'

        # ============================
        # 6. TRANSFORM TO CSV ROWS
        # ============================
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Transforming CVE data into Ninja CSV format" -Sev 'Debug'
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
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Skipped $SkippedCount vulnerabilities due to missing deviceName or cveId" -Sev 'Warning'
        }

        if ($CsvRows.Count -eq 0) {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "No valid CVEs found to upload for this tenant" -Sev 'Info'
            
            if ($Settings.report) {
                Set-CIPPStandardsCompareField -FieldName 'standards.NinjaCveSync' -FieldValue "No valid CVEs detected" -TenantFilter $TenantFilter
            }
            return
        }

        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Prepared $($CsvRows.Count) CVE rows for upload" -Sev 'Info'

        # ============================
        # 7. BUILD CSV BYTES (using helper function)
        # ============================
        $CsvBytes = New-VulnCsvBytes -Rows $CsvRows -Headers @($DeviceIdHeader, $CveIdHeader)
        
        if (-not $CsvBytes -or $CsvBytes.Length -eq 0) {
            throw "Failed to generate CSV bytes from vulnerability data"
        }
        
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Generated CSV payload: $($CsvBytes.Length) bytes" -Sev 'Debug'

        # ============================
        # 8. UPLOAD TO NINJAONE (using helper function)
        # ============================
        # Use the numeric scan group ID in the URL
        $UploadUri = "$NinjaBaseUrl/vulnerability/scan-groups/$ResolvedScanGroupId/upload"
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Uploading CVE CSV to NinjaOne (ScanGroup: '$ScanGroupName', ID: $ResolvedScanGroupId, Uri: $UploadUri)" -Sev 'Info'

        try {
            $Response = Invoke-NinjaOneVulnCsvUpload `
                -Uri $UploadUri `
                -CsvBytes $CsvBytes `
                -Headers $Headers
            
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Upload completed successfully" -Sev 'Info'
            
            # Log response if present
            if ($Response) {
                Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "NinjaOne response: $($Response | ConvertTo-Json -Compress)" -Sev 'Debug'
                
                # Check for common response patterns
                if ($Response.status -and $Response.status -ne "success") {
                    Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Upload may have issues. Response status: $($Response.status)" -Sev 'Warning'
                }
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
            Set-CIPPStandardsCompareField -FieldName "standards.NinjaCveSync" -FieldValue $ReportMessage -TenantFilter $TenantFilter
        }

        # ============================
        # 10. ALERT MODE
        # ============================
        if ($Settings.alert) {
            Write-StandardsAlert -message "Uploaded $($CsvRows.Count) CVEs to NinjaOne scan group '$ScanGroupName' (ID: $ResolvedScanGroupId)" -tenant $TenantFilter -standardName 'NinjaCveSync' -standardId $Settings.standardId
        }

        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Ninja CVE Sync completed successfully for $($CsvRows.Count) CVEs" -Sev 'Info'

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Ninja CVE Sync failed: $ErrorMessage" -Sev 'Error'
        
        if ($Settings.report) {
            Set-CIPPStandardsCompareField -FieldName "standards.NinjaCveSync" -FieldValue "Failed: $ErrorMessage" -TenantFilter $TenantFilter
        }
        
        throw $ErrorMessage
    }
}