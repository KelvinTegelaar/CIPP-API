function Push-ExecGenerateReportBuilderReport {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter,
        $TemplateName,
        $Blocks,
        $TemplateGUID,
        $IncludeRawAttachments,
        $Settings
    )

    try {
        if ([string]::IsNullOrEmpty($TenantFilter)) {
            throw 'TenantFilter is required'
        }

        # Page setup and branding for this report — page size, orientation, cover, footer,
        # watermark and which branding preset to render against. Carried through untouched: the
        # PDF is rendered in the browser, so this side only has to store what it was given.
        $ParsedSettings = $null
        if ($Settings) {
            if ($Settings -is [string]) {
                try { $ParsedSettings = ConvertFrom-Json -InputObject $Settings } catch { $ParsedSettings = $null }
            } else {
                $ParsedSettings = $Settings
            }
        }

        # Parse Blocks
        $ParsedBlocks = @()
        if ($Blocks) {
            if ($Blocks -is [string]) {
                $ParsedBlocks = @(ConvertFrom-Json -InputObject $Blocks)
            } else {
                $ParsedBlocks = @($Blocks)
            }
        } elseif ($TemplateGUID) {
            # A schedule that references a template by GUID follows the template: blocks, page
            # setup and name are read fresh on every run, so edits made to the template after the
            # schedule was created are picked up without recreating the schedule.
            $TemplateTable = Get-CippTable -tablename 'templates'
            $Template = Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq 'ReportBuilderTemplate' and RowKey eq '$($TemplateGUID)'"
            if (-not $Template -or -not $Template.JSON) {
                throw "Report template $TemplateGUID was not found. It may have been deleted; recreate the schedule from a saved template."
            }
            $TemplateData = ConvertFrom-Json -InputObject $Template.JSON
            $ParsedBlocks = @($TemplateData.Blocks)
            if ($TemplateData.Name) {
                $TemplateName = $TemplateData.Name
            }
            # A schedule created before page setup existed passes no Settings, so fall back to
            # whatever the template itself was saved with.
            if (-not $ParsedSettings -and $TemplateData.Settings) {
                $ParsedSettings = $TemplateData.Settings
            }
        }

        if ($ParsedBlocks.Count -eq 0) {
            throw 'No blocks provided and no template found'
        }

        # Licence assignments come out of the users cache as objects carrying skuId GUIDs; a
        # report reader wants product names. The tenant's LicenseOverview cache already carries
        # the display name per SKU with the ExcludedLicenses table applied, so cells shaped like
        # licence assignments render through it: known SKUs become their product name and
        # excluded SKUs drop out, matching every other licence view in CIPP. Without overview
        # data the cell is left untouched rather than guessed at.
        $LicenseNamesBySkuId = @{}
        if ($ParsedBlocks | Where-Object { $_.type -eq 'database' -and $_.dbType }) {
            try {
                foreach ($License in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'LicenseOverview' -Fields 'License', 'skuId')) {
                    if ($License.skuId) { $LicenseNamesBySkuId[([string]$License.skuId).ToLowerInvariant()] = [string]$License.License }
                }
            } catch {
                Write-LogMessage -API 'ReportBuilder' -tenant $TenantFilter -message "Could not load the licence overview cache; licence columns will show raw SKU ids: $($_.Exception.Message)" -Sev 'Warning'
            }
        }
        $ResolveCellValue = {
            param($Value, $Header, $Row)
            # Windows 365 Cloud PCs never report BitLocker (isEncrypted stays false) although
            # their disks are platform-encrypted by Azure - rendered as a distinct state so the
            # device is not flagged as an encryption risk. Mirrored by the report builder's
            # client-side preview (formatDatabaseContent).
            if ($Header -eq 'isEncrypted' -and $Value -ne $true -and $Row -and (Test-CIPPCloudPCDevice -Device $Row)) {
                return 'Encrypted (platform-managed)'
            }
            $Items = @($Value)
            if ($LicenseNamesBySkuId.Count -eq 0 -or $Items.Count -eq 0 -or $null -eq $Items[0] -or -not $Items[0].PSObject.Properties['skuId']) {
                return $Value
            }
            $Names = foreach ($Assignment in $Items) {
                $Name = $LicenseNamesBySkuId[([string]$Assignment.skuId).ToLowerInvariant()]
                if ($Name) { $Name }
            }
            return (@($Names) -join ', ')
        }

        # For test blocks that are NOT static, fetch fresh test results
        $TestResults = $null
        $HasLiveTests = $ParsedBlocks | Where-Object { $_.type -eq 'test' -and $_.static -ne $true }
        if ($HasLiveTests) {
            $TestTable = Get-CippTable -tablename 'CippTestResults'
            $TestFilter = "PartitionKey eq '$TenantFilter'"
            $TestResults = @(Get-CIPPAzDataTableEntity @TestTable -Filter $TestFilter)
        }

        # Build enriched blocks with fresh content
        $EnrichedBlocks = @($ParsedBlocks | ForEach-Object {
                $Block = $_

                # Enrich live test blocks
                if ($Block.type -eq 'test' -and $Block.static -ne $true -and $TestResults) {
                    $TestResult = $TestResults | Where-Object { $_.TestId -eq $Block.testId -or $_.RowKey -eq $Block.testId } | Select-Object -First 1
                    if ($TestResult) {
                        if ($TestResult.TestType -eq 'Custom' -and $TestResult.ResultDataJson -and $TestResult.MarkdownTemplate) {
                            $Block.content = $TestResult.MarkdownTemplate
                        } elseif ($TestResult.ResultMarkdown) {
                            $Block | Add-Member -NotePropertyName 'content' -NotePropertyValue $TestResult.ResultMarkdown -Force
                        }
                    }
                }

                # Enrich database blocks
                if ($Block.type -eq 'database' -and $Block.dbType) {
                    try {
                        $DbData = New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Block.dbType
                        if ($null -ne $DbData) {
                            $FirstItem = if ($DbData -is [array]) { $DbData[0] } else { $DbData }
                            $SelectedHeaders = @($Block.selectedHeaders)
                            if ($SelectedHeaders.Count -eq 0) {
                                $ExcludedHeaders = @('id', 'rowkey', 'partitionkey', 'etag', 'timestamp')
                                $AllHeaders = @($FirstItem.PSObject.Properties.Name | Where-Object { $_.ToLower() -notin $ExcludedHeaders }) | Sort-Object
                                $SelectedHeaders = $AllHeaders
                            }
                            $Format = if ($Block.format) { $Block.format } else { 'text' }
                            $FilteredData = @(@($DbData) | ForEach-Object {
                                    $Row = $_
                                    $Obj = [ordered]@{}
                                    foreach ($Header in $SelectedHeaders) {
                                        $Val = $Row.$Header
                                        $Obj[$Header] = if ($null -ne $Val) { & $ResolveCellValue $Val $Header $Row } else { '' }
                                    }
                                    [PSCustomObject]$Obj
                                })

                            $BlockContent = switch ($Format) {
                                'json' {
                                    ConvertTo-Json -InputObject @($FilteredData) -Depth 10 -Compress
                                }
                                'csv' {
                                    ($FilteredData | ConvertTo-Csv -NoTypeInformation) -join "`n"
                                }
                                default {
                                    $HeaderLine = '| ' + ($SelectedHeaders -join ' | ') + ' |'
                                    $SeparatorLine = '| ' + (($SelectedHeaders | ForEach-Object { '---' }) -join ' | ') + ' |'
                                    $DataLines = @($FilteredData | ForEach-Object {
                                            $DataRow = $_
                                            $Cells = $SelectedHeaders | ForEach-Object {
                                                $Val = $DataRow.$_
                                                if ($null -eq $Val) { '' }
                                                elseif ($Val -is [PSCustomObject] -or $Val -is [hashtable]) { ConvertTo-Json -InputObject $Val -Depth 5 -Compress }
                                                else { "$Val" -replace '\|', '\|' -replace "`n", ' ' }
                                            }
                                            '| ' + ($Cells -join ' | ') + ' |'
                                        })
                                    (@($HeaderLine, $SeparatorLine) + $DataLines) -join "`n"
                                }
                            }
                            $Block | Add-Member -NotePropertyMembers ([ordered]@{
                                    content = $BlockContent
                                    static  = $true
                                }) -Force
                        } else {
                            $Block | Add-Member -NotePropertyName 'content' -NotePropertyValue 'No data available for this data source.' -Force
                        }
                    } catch {
                        $DbError = Get-CippException -Exception $_
                        Write-LogMessage -API 'ReportBuilder' -tenant $TenantFilter -message "Failed to fetch database data for type $($Block.dbType): $($DbError.NormalizedError)" -Sev 'Warning' -LogData $DbError
                        $Block | Add-Member -NotePropertyName 'content' -NotePropertyValue "Error fetching data: $($DbError.NormalizedError)" -Force
                    }
                }

                $Block
            })

        # Store the generated report
        $ReportGUID = (New-Guid).GUID
        $ReportTable = Get-CippTable -tablename 'ReportBuilderReports'
        $ReportEntity = @{
            PartitionKey = $TenantFilter
            RowKey       = [string]$ReportGUID
            TemplateName = [string]($TemplateName ?? 'Scheduled Report')
            TenantFilter = [string]$TenantFilter
            Blocks       = [string](ConvertTo-Json -InputObject @($EnrichedBlocks) -Depth 20 -Compress)
            GeneratedAt  = [string](Get-Date).ToString('o')
            Status       = 'Completed'
            Settings     = if ($ParsedSettings) { [string](ConvertTo-Json -InputObject $ParsedSettings -Depth 10 -Compress) } else { '' }
        }

        Add-CIPPAzDataTableEntity @ReportTable -Entity $ReportEntity -Force
        Write-LogMessage -API 'ReportBuilder' -tenant $TenantFilter -message "Generated report builder report '$TemplateName' with GUID $ReportGUID" -Sev 'Info'

        # Build result message with direct link
        $CippConfigTable = Get-CippTable -tablename Config
        $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
        $ReportLink = if ($CippConfig.Value) {
            "https://$($CippConfig.Value)/tools/report-builder/view?id=$ReportGUID"
        } else { $null }
        $ResultMessage = "Successfully generated report '$TemplateName' for $TenantFilter (GUID: $ReportGUID)"
        if ($ReportLink) {
            $ResultMessage += ". View report: $ReportLink"
        }

        # Build file attachments for database blocks if requested
        if ($IncludeRawAttachments -eq 'true') {
            $TaskAttachments = @()
            foreach ($Block in $EnrichedBlocks) {
                if ($Block.type -ne 'database' -or -not $Block.dbType) { continue }
                $Format = if ($Block.format) { $Block.format } else { 'csv' }
                $FileName = "$($Block.title ?? $Block.dbType)_$TenantFilter"
                $FileName = $FileName -replace '[^a-zA-Z0-9_\-]', '_'
                switch ($Format) {
                    'json' {
                        $FileContent = $Block.content
                        $FileName += '.json'
                        $ContentType = 'application/json'
                    }
                    'csv' {
                        $FileContent = $Block.content
                        $FileName += '.csv'
                        $ContentType = 'text/csv'
                    }
                    default {
                        # For text/markdown, export as CSV for attachment
                        try {
                            $DbData = New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Block.dbType
                            $SelectedHeaders = @($Block.selectedHeaders)
                            $Rows = @(@($DbData) | ForEach-Object {
                                    $Row = $_
                                    $Obj = [ordered]@{}
                                    foreach ($Header in $SelectedHeaders) {
                                        $Val = $Row.$Header
                                        $Obj[$Header] = if ($null -ne $Val) { & $ResolveCellValue $Val $Header $Row } else { '' }
                                    }
                                    [PSCustomObject]$Obj
                                })
                            $FileContent = ($Rows | ConvertTo-Csv -NoTypeInformation) -join "`n"
                        } catch {
                            $FileContent = $Block.content
                        }
                        $FileName += '.csv'
                        $ContentType = 'text/csv'
                    }
                }
                $Bytes = [System.Text.Encoding]::UTF8.GetBytes($FileContent)
                $Base64 = [Convert]::ToBase64String($Bytes)
                $TaskAttachments += @{
                    Name        = $FileName
                    ContentType = $ContentType
                    ContentBytes = $Base64
                }
            }
            if ($TaskAttachments.Count -gt 0) {
                return @{
                    TaskAttachments = $TaskAttachments
                    Results         = $ResultMessage
                }
            }
        }

        return $ResultMessage
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'ReportBuilder' -tenant $TenantFilter -message "Report generation error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return "Error generating report: $($ErrorMessage.NormalizedError)"
    }
}
