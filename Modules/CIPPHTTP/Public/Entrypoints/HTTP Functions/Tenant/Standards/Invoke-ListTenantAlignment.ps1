function Invoke-ListTenantAlignment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    .DESCRIPTION
        Lists tenant alignment data showing how well tenants conform to their assigned standards templates.

        Pass summary=true for the estate roll-up only: per-tenant averages collapsed into score
        buckets, the overall average, the lowest-scoring tenants and the pending-deviation totals.
        The row list is one entry per tenant per standard, so an estate-wide caller that only
        renders those aggregates would otherwise pull tenants x standards rows to compute a
        handful of numbers.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Granular = $Request.Query.granular -eq $true
    $Summary = $Request.Query.summary -eq $true
    # Granular flattens to one row per standard; it is a detail view and never a summary source.
    if ($Summary) { $Granular = $false }
    try {
        # Use the new Get-CIPPTenantAlignment function to get alignment data
        $AlignmentData = Get-CIPPTenantAlignment

        # Build a GUID -> displayName lookup from the templates table for all template types
        $TemplateLookup = @{}
        if ($Granular) {
            $TemplateTable = Get-CippTable -tablename 'templates'
            $TemplatePartitions = @('IntuneTemplate', 'ConditionalAccessTemplate', 'QuarantineTemplate', 'IntuneReusableSettingTemplate')
            foreach ($Partition in $TemplatePartitions) {
                Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq '$Partition'" | ForEach-Object {
                    $TemplateRow = $_
                    try {
                        $Parsed = $TemplateRow.JSON | ConvertFrom-Json -ErrorAction Stop
                        $DisplayName = $Parsed.displayName ?? $Parsed.Displayname ?? $Parsed.DisplayName ?? $Parsed.name ?? $TemplateRow.RowKey
                        $TemplateLookup[$TemplateRow.RowKey] = $DisplayName
                    } catch {
                        $TemplateLookup[$TemplateRow.RowKey] = $TemplateRow.RowKey
                    }
                }
            }
        }

        $Results = if ($Granular) {
            # Flatten ComparisonResults into one row per tenant+standard
            $AlignmentData | ForEach-Object {
                $Row = $_
                $TemplateName = $Row.StandardName
                $TemplateId = $Row.StandardId
                $StandardType = $Row.standardType ? $Row.standardType : 'Classic Standard'
                $Row.ComparisonDetails | ForEach-Object {
                    $Detail = $_
                    try {
                        $StandardId = $Detail.StandardName
                        $FriendlyType = $StandardType
                        $ResolvedName = if ($StandardId -and $StandardId -match '^standards\.(\w+Template)\.(.+)$') {
                            $MatchType = $Matches[1]
                            $MatchValue = $Matches[2]
                            $LookupKey = if ($MatchType -eq 'QuarantineTemplate') {
                                $KeyBytes = [byte[]]::new($MatchValue.Length / 2)
                                for ($i = 0; $i -lt $KeyBytes.Length; $i++) {
                                    $KeyBytes[$i] = [Convert]::ToByte($MatchValue.Substring($i * 2, 2), 16)
                                }
                                [System.Text.Encoding]::UTF8.GetString($KeyBytes)
                            } else {
                                $MatchValue
                            }
                            $PolicyName = $TemplateLookup[$LookupKey] ?? $LookupKey
                            $FriendlyType = switch ($MatchType) {
                                'IntuneTemplate' { 'Intune Template' }
                                'ConditionalAccessTemplate' { 'Conditional Access Template' }
                                'QuarantineTemplate' { 'Quarantine Template' }
                                'ReusableSettingsTemplate' { 'Reusable Settings Template' }
                                default { $MatchType }
                            }
                            "$FriendlyType - $PolicyName"
                        } else {
                            $StandardId
                        }
                        [PSCustomObject]@{
                            tenantFilter         = $Row.TenantFilter
                            templateName         = $TemplateName
                            templateId           = $TemplateId
                            templateType         = $Row.standardType
                            standardType         = $FriendlyType
                            standardId           = $StandardId
                            standardName         = $ResolvedName
                            complianceStatus     = $Detail.ComplianceStatus
                            compliant            = $Detail.Compliant
                            deviationStatus      = $Detail.DeviationStatus
                            licenseAvailable     = $Detail.LicenseAvailable
                            currentValue         = $Detail.CurrentValue
                            expectedValue        = $Detail.ExpectedValue
                            latestDataCollection = $Row.LatestDataCollection
                        }
                    } catch {
                        Write-LogMessage -API $APIName -tenant $Row.TenantFilter -message "Failed to flatten alignment row for $($Row.TenantFilter)/$($Detail.StandardName): $($_.Exception.Message)" -sev Warning
                    }
                }
            }
        } else {
            # Transform the data to match the expected API response format
            $AlignmentData | ForEach-Object {
                [PSCustomObject]@{
                    tenantFilter             = $_.TenantFilter
                    standardName             = $_.StandardName
                    standardType             = $_.StandardType ? $_.StandardType : 'Classic Standard'
                    standardId               = $_.StandardId
                    alignmentScore           = $_.AlignmentScore
                    LicenseMissingPercentage = $_.LicenseMissingPercentage
                    combinedAlignmentScore   = $_.CombinedScore
                    pendingDeviationsCount   = $_.PendingDeviationsCount
                    deniedDeviationsCount    = $_.DeniedDeviationsCount
                    latestDataCollection     = $_.LatestDataCollection
                }
            }
        }

        if ($Summary) {
            # Average a tenant's rows before bucketing: five templates is still one tenant.
            $ByTenant = @{}
            $PendingByTenant = @{}
            $PendingDeviations = 0
            foreach ($Row in @($Results)) {
                $Key = [string]$Row.tenantFilter
                if ([string]::IsNullOrWhiteSpace($Key)) { continue }

                $Score = [double](($Row.combinedAlignmentScore ?? $Row.alignmentScore) ?? 0)
                if (-not $ByTenant.ContainsKey($Key)) { $ByTenant[$Key] = @{ Total = 0.0; Count = 0 } }
                $ByTenant[$Key].Total += $Score
                $ByTenant[$Key].Count++

                $Pending = [int]($Row.pendingDeviationsCount ?? 0)
                if ($Pending -gt 0) {
                    $PendingDeviations += $Pending
                    $PendingByTenant[$Key] = ($PendingByTenant[$Key] ?? 0) + $Pending
                }
            }

            $TenantLookupByDomain = @{}
            foreach ($KnownTenant in (Get-Tenants -IncludeErrors)) {
                if ($KnownTenant.defaultDomainName) { $TenantLookupByDomain[$KnownTenant.defaultDomainName] = $KnownTenant }
            }

            $Scores = [System.Collections.Generic.List[object]]::new()
            foreach ($Key in $ByTenant.Keys) {
                $Bucket = $ByTenant[$Key]
                $Average = if ($Bucket.Count) { [math]::Round($Bucket.Total / $Bucket.Count) } else { 0 }
                $Scores.Add([PSCustomObject]@{
                        Tenant = $Key
                        Name   = $TenantLookupByDomain[$Key].displayName ?? $Key
                        Score  = [int]$Average
                    })
            }

            $Buckets = [ordered]@{ Strong = 0; Good = 0; Weak = 0; Poor = 0 }
            foreach ($Entry in $Scores) {
                if ($Entry.Score -ge 90) { $Buckets['Strong']++ }
                elseif ($Entry.Score -ge 75) { $Buckets['Good']++ }
                elseif ($Entry.Score -ge 50) { $Buckets['Weak']++ }
                else { $Buckets['Poor']++ }
            }

            $Overall = if ($Scores.Count) {
                [int][math]::Round((($Scores | Measure-Object -Property Score -Sum).Sum) / $Scores.Count)
            } else { 0 }

            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{
                        Average            = $Overall
                        ScoredTenantCount  = $Scores.Count
                        Buckets            = [PSCustomObject]$Buckets
                        Lowest             = @($Scores | Sort-Object -Property Score, Tenant | Select-Object -First 4)
                        PendingDeviations  = $PendingDeviations
                        PendingTenantCount = $PendingByTenant.Keys.Count
                    }
                })
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($Results)
            })
    } catch {
        $ErrorDetail = "$($_.Exception.Message) at $($_.InvocationInfo.PositionMessage -replace '\r?\n', ' ')"
        Write-LogMessage -API $APIName -message "Failed to get tenant alignment data: $ErrorDetail" -sev Error -LogData (Get-CippException -Exception $_)
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ error = "Failed to get tenant alignment data: $($_.Exception.Message)" }
            })
    }
}
