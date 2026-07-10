function Invoke-ListTenantAlignment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    .DESCRIPTION
        Lists tenant alignment data showing how well tenants conform to their assigned standards templates.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Granular = $Request.Query.granular -eq 'true'
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
