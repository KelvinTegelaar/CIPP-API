function Invoke-NinjaOneCveSyncTenant {
    [CmdletBinding()]
    param (
        $QueueItem
    )

    try {
        $MappedTenant = $QueueItem.MappedTenant

        $Customer = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -eq $MappedTenant.RowKey }

        if (($Customer | Measure-Object).count -ne 1) {
            throw "Unable to match the received ID to a tenant. QueueItem: $($QueueItem | ConvertTo-Json -Depth 10 | Out-String)"
        }

        $TenantFilter = $Customer.defaultDomainName

        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Starting CVE sync for $($Customer.displayName)" -sev 'Info'

        # Load NinjaOne config
        $Table         = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).NinjaOne

        if (-not $Configuration -or -not $Configuration.Instance) {
            throw 'NinjaOne configuration is missing or incomplete'
        }

        $ScanGroupPrefix = $Configuration.CveSyncPrefix ?? ''
        $ScanGroupName   = "$ScanGroupPrefix$TenantFilter"
        $NinjaBaseUrl    = "https://$($Configuration.Instance)/api/v2"

        # Get token
        $Token = Get-NinjaOneToken -configuration $Configuration

        if (-not $Token -or -not $Token.access_token) {
            throw 'Failed to retrieve NinjaOne access token'
        }

        $Headers = @{ Authorization = "Bearer $($Token.access_token)" }

        # Get scan groups
        $ScanGroups = Invoke-RestMethod -Method Get -Uri "$NinjaBaseUrl/vulnerability/scan-groups" -Headers $Headers -TimeoutSec 30 -ErrorAction Stop

        if (-not $ScanGroups) {
            throw 'Scan groups response was empty'
        }

        # Resolve scan group for this tenant
        $ResolvedScanGroup = $ScanGroups | Where-Object { $_.groupName -eq $ScanGroupName }

        if (-not $ResolvedScanGroup) {
            $Available = ($ScanGroups | Select-Object -First 10 | ForEach-Object { "ID $($_.id): $($_.groupName)" }) -join ', '
            throw "Scan group '$ScanGroupName' not found. Available: $Available"
        }

        $ResolvedScanGroupId = $ResolvedScanGroup.id
        $DeviceIdHeader      = $ResolvedScanGroup.deviceIdHeader
        $CveIdHeader         = $ResolvedScanGroup.cveIdHeader

        if ([string]::IsNullOrWhiteSpace($DeviceIdHeader) -or [string]::IsNullOrWhiteSpace($CveIdHeader)) {
            throw 'Scan group missing required header config'
        }

        # Pull Defender TVM data
        $AllVulns = Get-DefenderTvmRaw -TenantId $TenantFilter -MaxPages 0

        if (-not $AllVulns) {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message 'No vulnerability data returned — skipping' -sev 'Warning'
            return $true
        }

        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Retrieved $($AllVulns.Count) vulnerabilities" -sev 'Info'

        # Filter CIPP exceptions
        $ExceptionsTable      = Get-CIPPTable -TableName 'CveExceptions'
        $AllExceptions        = Get-CIPPAzDataTableEntity @ExceptionsTable
        $ApplicableExceptions = $AllExceptions | Where-Object { $_.RowKey -eq $TenantFilter -or $_.RowKey -eq 'ALL' }

        if ($ApplicableExceptions) {
            $ExceptedCveIds = $ApplicableExceptions | Select-Object -ExpandProperty cveId -Unique
            $BeforeCount    = $AllVulns.Count
            $AllVulns       = $AllVulns | Where-Object { $_.cveId -notin $ExceptedCveIds }
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Filtered $($BeforeCount - $AllVulns.Count) excepted CVEs — $($AllVulns.Count) remaining" -sev 'Info'
        }

        # Build CSV rows
        $CsvRows      = [System.Collections.Generic.List[object]]::new()
        $SkippedCount = 0

        foreach ($Item in $AllVulns) {
            if ([string]::IsNullOrWhiteSpace($Item.cveId) -or [string]::IsNullOrWhiteSpace($Item.deviceName)) {
                $SkippedCount++
                continue
            }
            [void]$CsvRows.Add([PSCustomObject]@{
                $DeviceIdHeader = $Item.deviceName.Trim()
                $CveIdHeader    = $Item.cveId.Trim()
            })
        }

        if ($SkippedCount -gt 0) {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Skipped $SkippedCount rows (missing deviceName or cveId)" -sev 'Warning'
        }

        $CsvBytes = New-VulnCsvBytes -Rows $CsvRows -Headers @($DeviceIdHeader, $CveIdHeader)

        if (-not $CsvBytes -or $CsvBytes.Length -eq 0) {
            throw 'Failed to generate CSV bytes'
        }

        # Upload and poll for completion
        $UploadUri = "$NinjaBaseUrl/vulnerability/scan-groups/$ResolvedScanGroupId/upload"
        $PollUri   = "$NinjaBaseUrl/vulnerability/scan-groups/$ResolvedScanGroupId"
        $Response  = Invoke-NinjaOneVulnCsvUpload -Uri $UploadUri -PollUri $PollUri -CsvBytes $CsvBytes -Headers $Headers

        $FinalStatus    = $Response.status ?? 'unknown'
        $ProcessedCount = $Response.recordsProcessed ?? '?'

        if ($FinalStatus -eq 'COMPLETE') {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Complete — $($CsvRows.Count) CVEs sent to '$ScanGroupName', $ProcessedCount processed by NinjaOne" -sev 'Info'
        } elseif ($FinalStatus -eq 'IN_PROGRESS') {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Upload accepted — $($CsvRows.Count) CVEs sent to '$ScanGroupName', still processing (timed out polling)" -sev 'Warning'
        } else {
            Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Upload finished with status '$FinalStatus' for '$ScanGroupName', $ProcessedCount processed by NinjaOne" -sev 'Warning'
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'NinjaCveSync' -tenant $TenantFilter -message "Failed CVE sync: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
    }

    return $true
}
