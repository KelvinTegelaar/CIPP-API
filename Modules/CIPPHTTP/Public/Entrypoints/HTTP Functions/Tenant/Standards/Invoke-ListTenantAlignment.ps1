function Invoke-ListTenantAlignment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
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
            $TemplatePartitions = @('IntuneTemplate', 'ConditionalAccessTemplate', 'QuarantineTemplate')
            foreach ($Partition in $TemplatePartitions) {
                Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq '$Partition'" | ForEach-Object {
                    try {
                        $Parsed = $_.JSON | ConvertFrom-Json -ErrorAction Stop
                        $DisplayName = $Parsed.displayName ?? $Parsed.Displayname ?? $Parsed.DisplayName ?? $Parsed.name ?? $_.RowKey
                        $TemplateLookup[$_.RowKey] = $DisplayName
                    } catch {
                        $TemplateLookup[$_.RowKey] = $_.RowKey
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
                    $StandardId = $_.StandardName
                    $FriendlyType = $StandardType
                    $ResolvedName = if ($StandardId -match '^standards\.(\w+Template)\.(.+)$') {
                        $LookupKey = if ($Matches[1] -eq 'QuarantineTemplate') {
                            $KeyBytes = [byte[]]::new($Matches[2].Length / 2)
                            for ($i = 0; $i -lt $KeyBytes.Length; $i++) {
                                $KeyBytes[$i] = [Convert]::ToByte($Matches[2].Substring($i * 2, 2), 16)
                            }
                            [System.Text.Encoding]::UTF8.GetString($KeyBytes)
                        } else {
                            $Matches[2]
                        }
                        $PolicyName = $TemplateLookup[$LookupKey] ?? $LookupKey
                        $FriendlyType = switch ($Matches[1]) {
                            'IntuneTemplate' { 'Intune Template' }
                            'ConditionalAccessTemplate' { 'Conditional Access Template' }
                            'QuarantineTemplate' { 'Quarantine Template' }
                            default { $Matches[1] }
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
                        complianceStatus     = $_.ComplianceStatus
                        compliant            = $_.Compliant
                        deviationStatus      = $_.DeviationStatus
                        licenseAvailable     = $_.LicenseAvailable
                        currentValue         = $_.CurrentValue
                        expectedValue        = $_.ExpectedValue
                        latestDataCollection = $Row.LatestDataCollection
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
                    latestDataCollection     = $_.LatestDataCollection
                }
            }
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($Results)
            })
    } catch {
        Write-LogMessage -API $APIName -message "Failed to get tenant alignment data: $($_.Exception.Message)" -sev Error
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ error = "Failed to get tenant alignment data: $($_.Exception.Message)" }
            })
    }
}
