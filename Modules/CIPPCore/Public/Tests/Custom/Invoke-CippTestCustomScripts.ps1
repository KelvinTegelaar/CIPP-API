function Invoke-CippTestCustomScripts {
    <#
    .SYNOPSIS
    Run enabled custom scripts as CIPP tests
    #>
    param($Tenant)

    try {
        $Table = Get-CippTable -tablename 'CustomPowershellScripts'
        $Scripts = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CustomScript'")
        if (-not $Scripts) {
            return
        }

        $LatestScripts = $Scripts | Group-Object -Property ScriptGuid | ForEach-Object {
            $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
        }

        foreach ($Script in $LatestScripts) {
            $IsEnabled = if ($Script.PSObject.Properties['Enabled']) { [bool]$Script.Enabled } else { $true }
            if (-not $IsEnabled) {
                continue
            }
            $ShouldAlert = $false
            if ($Script.PSObject.Properties['AlertOnFailure']) {
                $ShouldAlert = [bool]$Script.AlertOnFailure
            }

            $TestId = "CustomScript-$($Script.ScriptGuid)"
            $ScriptName = if ([string]::IsNullOrWhiteSpace($Script.ScriptName)) { $TestId } else { $Script.ScriptName }
            try {
                $Result = New-CippCustomScriptExecution -ScriptGuid $Script.ScriptGuid -TenantFilter $Tenant -Parameters @{}
                $FailedRows = @($Result) | Where-Object {
                    $null -ne $_ -and
                    -not ($_ -is [bool] -and -not $_) -and
                    -not ($_ -is [string] -and [string]::IsNullOrWhiteSpace($_))
                }

                if ($FailedRows.Count -gt 0) {
                    $ResultDataJson = $FailedRows | ConvertTo-Json -Depth 10 -Compress
                    Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Custom' -Status 'Failed' -ResultDataJson $ResultDataJson -Risk ($Script.Risk ?? 'Medium') -Name $ScriptName -Pillar $Script.Pillar -UserImpact $Script.UserImpact -ImplementationEffort $Script.ImplementationEffort -Category 'Custom Script'
                    if ($ShouldAlert) {
                        Write-AlertMessage -tenant $Tenant -message "Custom script test failed: $ScriptName ($($Script.ScriptGuid))"
                    }
                } else {
                    Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Custom' -Status 'Passed' -ResultDataJson '[]' -Risk ($Script.Risk ?? 'Medium') -Name $ScriptName -Pillar $Script.Pillar -UserImpact $Script.UserImpact -ImplementationEffort $Script.ImplementationEffort -Category 'Custom Script'
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Custom' -Status 'Failed' -ResultMarkdown "Custom script execution failed: $($ErrorMessage.NormalizedError)" -Risk ($Script.Risk ?? 'Medium') -Name $ScriptName -Pillar $Script.Pillar -UserImpact $Script.UserImpact -ImplementationEffort $Script.ImplementationEffort -Category 'Custom Script'
                if ($ShouldAlert) {
                    Write-AlertMessage -tenant $Tenant -message "Custom script execution failed: $ScriptName ($($Script.ScriptGuid)) - $($ErrorMessage.NormalizedError)"
                }
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run custom script tests: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
