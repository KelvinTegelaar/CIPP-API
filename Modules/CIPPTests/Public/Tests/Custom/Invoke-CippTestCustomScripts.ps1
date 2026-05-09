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

        $LatestScripts = $Scripts | Group-Object -Property ScriptGuid | ForEach-Object {
            $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
        }

        if (-not [string]::IsNullOrWhiteSpace($ScriptGuid) -and $LatestScripts.Count -eq 0) {
            Write-Information "No latest custom script found for ScriptGuid: $ScriptGuid"
            return
        }

        foreach ($Script in $LatestScripts) {
            # We can't prefilter this on table lookup as each script version has its own Enabled property, so we need to check here if the latest version is enabled
            $IsEnabled = if ($Script.PSObject.Properties['Enabled']) { [bool]$Script.Enabled } else { $true }
            if (-not $IsEnabled) {
                continue
            }
            $ShouldAlert = $false
            if ($Script.PSObject.Properties['AlertOnFailure']) {
                $ShouldAlert = [bool]$Script.AlertOnFailure
            }

            $ResultMode = if ($Script.PSObject.Properties['ResultMode'] -and -not [string]::IsNullOrWhiteSpace($Script.ResultMode)) { $Script.ResultMode } else { 'Auto' }

            $TestId = "CustomScript-$($Script.ScriptGuid)"
            $ScriptName = if ([string]::IsNullOrWhiteSpace($Script.ScriptName)) { $TestId } else { $Script.ScriptName }
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

                if ($ShouldAlert -and $AutoStatus -eq 'Failed') {
                    Write-AlertMessage -tenant $Tenant -message "Custom script test failed: $ScriptName ($($Script.ScriptGuid))"
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
                if ($ShouldAlert -and $ResultMode -eq 'Auto') {
                    Write-AlertMessage -tenant $Tenant -message "Custom script execution failed: $ScriptName ($($Script.ScriptGuid)) - $($ErrorMessage.NormalizedError)"
                }
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run custom script tests: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
