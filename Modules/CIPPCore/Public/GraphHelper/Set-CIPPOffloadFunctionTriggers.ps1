function Set-CIPPOffloadFunctionTriggers {
    <#
    .SYNOPSIS
        Manages non-HTTP triggers on function apps based on offloading configuration.
    .DESCRIPTION
        Automatically detects if running on an offloaded function app (contains hyphen in name).
        If this is the main function app (no hyphen), checks the offloading state from Config table
        and disables/enables timer, activity, orchestrator, and queue triggers accordingly.
        Offloaded function apps (with hyphen) are skipped as they should have triggers enabled.
    .EXAMPLE
        Set-CIPPOffloadFunctionTriggers
        Automatically manages triggers based on current function app context and offloading state.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    # Get current function app name
    $FunctionAppName = $env:WEBSITE_SITE_NAME

    # Check if this is an offloaded function app (contains hyphen)
    if ($FunctionAppName -match '-') {
        return $true
    }

    # Get offloading state from Config table
    $Table = Get-CippTable -tablename 'Config'
    $OffloadConfig = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"
    $OffloadEnabled = [bool]$OffloadConfig.state

    # Determine resource group
    if ($env:WEBSITE_RESOURCE_GROUP) {
        $ResourceGroupName = $env:WEBSITE_RESOURCE_GROUP
    } else {
        $Owner = $env:WEBSITE_OWNER_NAME
        if ($env:WEBSITE_SKU -ne 'FlexConsumption' -and $Owner -match '^(?<SubscriptionId>[^+]+)\+(?<RGName>[^-]+(?:-[^-]+)*?)(?:-[^-]+webspace(?:-Linux)?)?$') {
            $ResourceGroupName = $Matches.RGName
        } else {
            throw 'Could not determine resource group. Please provide ResourceGroupName parameter.'
        }
    }

    # Define the triggers to disable when offloading is enabled
    $TargetedTriggers = @(
        'CIPPTimer'
        'CIPPActivityFunction'
        'CIPPOrchestrator'
        'CIPPQueueTrigger'
    )

    try {
        if ($OffloadEnabled -and $env:WEBSITE_SKU -ne 'FlexConsumption') {
            $AppSettings = @{}
            $SkippedTriggers = [System.Collections.Generic.List[string]]::new()
            foreach ($Trigger in $TargetedTriggers) {
                $SettingKey = "AzureWebJobs.$Trigger.Disabled"
                # Convert setting key to environment variable format (dots become underscores)
                $EnvVarName = $SettingKey -replace '\.', '_'
                $CurrentValue = [System.Environment]::GetEnvironmentVariable($EnvVarName)

                if ($CurrentValue -eq '1') {
                    Write-Verbose "Skipping $SettingKey - already set to 1"
                    $SkippedTriggers.Add($Trigger)
                } else {
                    $AppSettings[$SettingKey] = '1'
                    Write-Verbose "Setting $SettingKey = 1"
                }
            }

            # Update app settings only if there are changes to make
            if ($AppSettings.Count -gt 0) {
                if ($PSCmdlet.ShouldProcess($FunctionAppName, 'Disable non-HTTP triggers')) {
                    Update-CIPPAzFunctionAppSetting -Name $FunctionAppName -ResourceGroupName $ResourceGroupName -AppSetting $AppSettings | Out-Null
                    Write-Information "Successfully disabled $($AppSettings.Count) non-HTTP trigger(s) on $FunctionAppName"
                }
            }
        } else {
            $RemoveKeys = [System.Collections.Generic.List[string]]::new()
            $SkippedTriggers = [System.Collections.Generic.List[string]]::new()
            foreach ($Trigger in $TargetedTriggers) {
                $SettingKey = "AzureWebJobs.$Trigger.Disabled"
                # Convert setting key to environment variable format (dots become underscores)
                $EnvVarName = $SettingKey -replace '\.', '_'
                $CurrentValue = [System.Environment]::GetEnvironmentVariable($EnvVarName)

                if ([string]::IsNullOrEmpty($CurrentValue) -or $CurrentValue -ne '1') {
                    Write-Verbose "Skipping $SettingKey - already enabled or not set"
                    $SkippedTriggers.Add($Trigger)
                } else {
                    $RemoveKeys.Add($SettingKey)
                    Write-Verbose "Removing $SettingKey"
                }
            }

            # Update app settings with removal of keys only if there are changes to make
            if ($RemoveKeys.Count -gt 0) {
                if ($PSCmdlet.ShouldProcess($FunctionAppName, 'Re-enable non-HTTP triggers')) {
                    Update-CIPPAzFunctionAppSetting -Name $FunctionAppName -ResourceGroupName $ResourceGroupName -AppSetting @{} -RemoveKeys $RemoveKeys | Out-Null
                    Write-Information "Successfully re-enabled $($RemoveKeys.Count) non-HTTP trigger(s) on $FunctionAppName"
                }
            }
        }

        return $true
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-Warning "Failed to update trigger settings: $($ErrorMessage.NormalizedError)"
        return $false
    }
}
