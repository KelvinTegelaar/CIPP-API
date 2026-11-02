function Invoke-CippTestCustomScripts {
    <#
    .SYNOPSIS
    Run enabled custom scripts as CIPP tests
    #>
    param(
        $Tenant,
        [string]$ScriptGuid
    )

    try {
        $Table = Get-CippTable -tablename 'CustomPowershellScripts'
        $Filter = "PartitionKey eq 'CustomScript' and ScriptGuid eq '$ScriptGuid'"
        $Scripts = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)
        if (-not $Scripts) {
            return
        }

        # Pick the latest version per ScriptGuid in a single pass instead of the
        # original Group-Object | ForEach-Object { Sort-Object | Select -First 1 }
        # pipeline (item 8).
        $LatestByGuid = @{}
        foreach ($S in $Scripts) {
            $Guid = $S.ScriptGuid
            if (-not $Guid) { continue }
            $Existing = $LatestByGuid[$Guid]
            if (-not $Existing -or [int]$S.Version -gt [int]$Existing.Version) {
                $LatestByGuid[$Guid] = $S
            }
        }
        $LatestScripts = @($LatestByGuid.Values)

        if (-not [string]::IsNullOrWhiteSpace($ScriptGuid) -and $LatestScripts.Count -eq 0) {
            Write-Information "No latest custom script found for ScriptGuid: $ScriptGuid"
            return
        }

        foreach ($Script in $LatestScripts) {
            # Cache PSObject property lookups once per script so we don't pay the
            # member-resolution cost repeatedly inside the hot loop (item 13).
            $Props = $Script.PSObject.Properties
            $EnabledProp = $Props['Enabled']
            $AlertProp = $Props['AlertOnFailure']
            $ResultModeProp = $Props['ResultMode']
            $AlertStatusesProp = $Props['AlertStatuses']

            # We can't prefilter this on table lookup as each script version has its own Enabled property, so we need to check here if the latest version is enabled
            $IsEnabled = if ($EnabledProp) { [bool]$EnabledProp.Value } else { $true }
            if (-not $IsEnabled) {
                continue
            }
            $ShouldAlert = if ($AlertProp) { [bool]$AlertProp.Value } else { $false }

            $ResultMode = if ($ResultModeProp -and -not [string]::IsNullOrWhiteSpace($ResultModeProp.Value)) { $ResultModeProp.Value } else { 'Auto' }

            $TestId = "CustomScript-$($Script.ScriptGuid)"
            $ScriptName = if ([string]::IsNullOrWhiteSpace($Script.ScriptName)) { $TestId } else { $Script.ScriptName }

            $AllStatuses = @('Passed', 'Failed', 'Info', 'Investigate')
            $AlertStatuses = @('Failed')
            if ($AlertStatusesProp -and -not [string]::IsNullOrWhiteSpace($AlertStatusesProp.Value)) {
                $RawAlertStatuses = [string]$AlertStatusesProp.Value
                if ($RawAlertStatuses.TrimStart().StartsWith('[')) {
                    $AlertStatuses = @($RawAlertStatuses | ConvertFrom-Json)
                } else {
                    $AlertStatuses = @($RawAlertStatuses)
                }
            }
            # 'All' alerts on every result status.
            if ($AlertStatuses -contains 'All') {
                $AlertStatuses = $AllStatuses
            }

            try {
                $Result = New-CippCustomScriptExecution -ScriptGuid $Script.ScriptGuid -TenantFilter $Tenant -Parameters @{}

                # Check for explicit status wrapper: @{ CIPPStatus = 'Pass'|'Fail'|'Info'; CIPPResults = @(...); CIPPResultMarkdown = '...' }
                $ExplicitStatus = $null
                $ExplicitMarkdown = $null
                $ResultData = $Result
                if ($Result -is [hashtable] -and $Result.ContainsKey('CIPPStatus')) {
                    $ExplicitStatus = $Result['CIPPStatus']
                    $ResultData = if ($Result.ContainsKey('CIPPResults')) { $Result['CIPPResults'] } else { $null }
                    $ExplicitMarkdown = if ($Result.ContainsKey('CIPPResultMarkdown')) { $Result['CIPPResultMarkdown'] } else { $null }
                } elseif ($Result -is [PSCustomObject] -and $Result.PSObject.Properties['CIPPStatus']) {
                    $ExplicitStatus = $Result.CIPPStatus
                    $ResultData = if ($Result.PSObject.Properties['CIPPResults']) { $Result.CIPPResults } else { $null }
                    $ExplicitMarkdown = if ($Result.PSObject.Properties['CIPPResultMarkdown']) { $Result.CIPPResultMarkdown } else { $null }
                }

                $FailedRows = @($ResultData) | Where-Object {
                    $null -ne $_ -and
                    -not ($_ -is [bool] -and -not $_) -and
                    -not ($_ -is [string] -and [string]::IsNullOrWhiteSpace($_))
                }

                # Determine final status based on ResultMode
                $ResultDataJson = if ($FailedRows.Count -gt 0) { $FailedRows | ConvertTo-Json -Depth 10 -Compress } else { '[]' }

                # Auto-detected status from output, then apply explicit override if present
                $AutoStatus = if ($FailedRows.Count -gt 0) { 'Failed' } else { 'Passed' }
                $ValidExplicitStatuses = @('Passed', 'Failed', 'Info', 'Investigate')
                if ($ExplicitStatus -and $ExplicitStatus -in $ValidExplicitStatuses) {
                    $AutoStatus = $ExplicitStatus
                }

                $FinalStatus = switch ($ResultMode) {
                    'AlwaysPass' { 'Passed' }
                    'AlwaysInfo' { 'Info' }
                    'AlwaysInvestigate' { 'Investigate' }
                    default { $AutoStatus }
                }

                $ResultMarkdown = if (-not [string]::IsNullOrWhiteSpace($ExplicitMarkdown)) { $ExplicitMarkdown } else { '' }
                Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Custom' -Status $FinalStatus -ResultDataJson $ResultDataJson -ResultMarkdown $ResultMarkdown -Risk ($Script.Risk ?? 'Medium') -Name $ScriptName -Pillar $Script.Pillar -UserImpact $Script.UserImpact -ImplementationEffort $Script.ImplementationEffort -Category 'Custom Script'

                if ($ShouldAlert -and $FinalStatus -in $AlertStatuses) {
                    # Logbook entry for the UI/audit trail. Uses API 'CustomTests' + a non-alert
                    # severity so Push-SchedulerCIPPNotifications does not re-ship it.
                    Write-LogMessage -API 'CustomTests' -tenant $Tenant -message "Custom script test '$ScriptName' returned status '$FinalStatus' ($($Script.ScriptGuid))" -sev Info
                    # Emit an alert record. Delivery is batched per-tenant by Invoke-CIPPTestCollection
                    # after the whole suite runs (Send-CIPPCustomTestAlert). Manual single-test runs
                    # via Push-CIPPTest discard this, so they intentionally do not ship an alert.
                    [PSCustomObject]@{
                        CippCustomTestAlert = $true
                        TestId              = $TestId
                        ScriptGuid          = $Script.ScriptGuid
                        ScriptName          = $ScriptName
                        Status              = $FinalStatus
                        Risk                = $Script.Risk ?? 'Medium'
                        Pillar              = $Script.Pillar
                        FailedRows          = $FailedRows
                        ResultMarkdown      = $ResultMarkdown
                        ErrorMessage        = $null
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $FinalStatus = switch ($ResultMode) {
                    'AlwaysPass' { 'Passed' }
                    'AlwaysInfo' { 'Info' }
                    'AlwaysInvestigate' { 'Investigate' }
                    default { 'Failed' }
                }
                Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Custom' -Status $FinalStatus -ResultMarkdown "Custom script execution failed: $($ErrorMessage.NormalizedError)" -Risk ($Script.Risk ?? 'Medium') -Name $ScriptName -Pillar $Script.Pillar -UserImpact $Script.UserImpact -ImplementationEffort $Script.ImplementationEffort -Category 'Custom Script'
                if ($ShouldAlert -and $FinalStatus -in $AlertStatuses) {
                    Write-LogMessage -API 'CustomTests' -tenant $Tenant -message "Custom script execution failed: $ScriptName ($($Script.ScriptGuid)) - $($ErrorMessage.NormalizedError)" -sev Warning
                    [PSCustomObject]@{
                        CippCustomTestAlert = $true
                        TestId              = $TestId
                        ScriptGuid          = $Script.ScriptGuid
                        ScriptName          = $ScriptName
                        Status              = $FinalStatus
                        Risk                = $Script.Risk ?? 'Medium'
                        Pillar              = $Script.Pillar
                        FailedRows          = @()
                        ResultMarkdown      = ''
                        ErrorMessage        = $ErrorMessage.NormalizedError
                    }
                }
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CustomTests' -tenant $Tenant -message "Failed to run custom script tests: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
