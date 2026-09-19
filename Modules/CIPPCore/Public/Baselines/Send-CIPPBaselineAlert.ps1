function Send-CIPPBaselineAlert {
    <#
    .SYNOPSIS
        Queues a baseline deviation/remediation alert for the end-of-run digest.
    .DESCRIPTION
        Fires on the transition into Drift (alertEnabled), on auto-remediation
        (alertOnRemediate) 
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Result)

    try {
        $Item = $Result.Item
        $Definition = $null
        try { $Definition = Get-CIPPBaselineDefinition -Name $Item.BaseName } catch {}
        $Label = $Definition.label ?? $Item.BaseName ?? $Item.Standard
        $PolicyName = $Result.ExpectedValue.displayName
        if ($PolicyName -is [string] -and -not [string]::IsNullOrWhiteSpace($PolicyName) -and $PolicyName -notmatch '\.json$') {
            $Label = $PolicyName
        }
        $Description = "$($Definition.executiveText ?? $Definition.helpText)"
        if ($Description.Length -gt 280) { $Description = "$($Description.Substring(0, 277))..." }

        $SettingLabels = @{}
        $SettingOptions = @{}
        foreach ($ExpectedProperty in (($Definition.expected ?? [PSCustomObject]@{}).PSObject.Properties)) {
            if ($ExpectedProperty.Value -is [string] -and $ExpectedProperty.Value -match '^%(\w+)%$') {
                $Variable = $Definition.variables.($Matches[1])
                if ($Variable.label -and $Variable.label -notmatch '\?\s*$') { $SettingLabels[$ExpectedProperty.Name] = "$($Variable.label)" }
                if ($Variable.options) { $SettingOptions[$ExpectedProperty.Name] = @($Variable.options) }
            }
        }
        $FriendlySetting = {
            param($PropertyName)
            if ($SettingLabels.ContainsKey("$PropertyName")) { return $SettingLabels["$PropertyName"] }
            $Leaf = @("$PropertyName" -split '\.')[-1]
            $Spaced = $Leaf -creplace '([a-z0-9])([A-Z])', '$1 $2'
            if ($Spaced.Length -gt 0) { $Spaced.Substring(0, 1).ToUpper() + $Spaced.Substring(1) } else { "$PropertyName" }
        }
        $FriendlyValue = {
            param($PropertyName, $Value)
            if ($Value -is [bool]) { return $Value } # the template renders On/Off
            $Text = "$Value"
            $Option = @($SettingOptions["$PropertyName"]) | Where-Object { "$($_.value)" -eq $Text } | Select-Object -First 1
            if ($Option) { return "$($Option.label)" }
            if ($Text.Length -gt 200) { return "$($Text.Substring(0, 197))..." }
            $Text
        }
        $Differences = @(($Result.Diff ?? $Result.RowDiff) | Where-Object { $_ } | Select-Object -First 12 | ForEach-Object {
                [PSCustomObject]@{
                    Property      = & $FriendlySetting $_.Property
                    ExpectedValue = & $FriendlyValue $_.Property $_.ExpectedValue
                    ReceivedValue = & $FriendlyValue $_.Property $_.ReceivedValue
                }
            })

        $RunId = if ($script:CippBaselineRunIdStorage) { $script:CippBaselineRunIdStorage.Value } else { '' }
        $Table = Get-CippTable -tablename 'BaselineAlertQueue'
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey    = "$($Item.TenantFilter)"
            RowKey          = [string](New-Guid).Guid
            Event           = "$($Result.AlertEvent)"
            Standard        = "$($Item.Standard)"
            Label           = "$Label"
            Description     = "$Description"
            Category        = "$($Definition.cat)"
            Baseline        = "$($Item.SourceTemplate)"
            Stage           = "$($Item.Stage)"
            Differences     = "$(ConvertTo-Json -Compress -Depth 10 -InputObject $Differences)"
            ConflictWith    = "$(@($Item.ConflictWith) -join ', ')"
            AlertEmails     = "$($Item.AlertEmails)"
            AlertWebhookUrl = "$($Item.AlertWebhookUrl)"
            RunId           = "$RunId"
        }
    } catch {
        Write-LogMessage -API 'Baselines' -tenant $Result.Item.TenantFilter -message "Failed to queue baseline alert for $($Result.Item.Standard): $($_.Exception.Message)" -Sev 'Error'
    }
}
