function Add-CIPPDefenderIndicator {
    <#
    .SYNOPSIS
        Adds Microsoft Defender for Endpoint custom indicators of one type and action to one tenant
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$TenantId,
        [Parameter(Mandatory = $true)]
        [string[]]$Values,
        [Parameter(Mandatory = $true)]
        [hashtable]$Template,
        $Headers,
        [string]$APIName = 'AddDefenderIndicator',
        [string]$QueueId
    )

    $Domain = $TenantFilter
    $IndicatorType = $Template.indicatorType
    $Action = $Template.action
    $Seen = [System.Collections.Generic.HashSet[string]]::new($Values, [System.StringComparer]::Ordinal)
    $Results = [System.Collections.Generic.List[object]]::new()
    $Failed = 0
    $Conflicts = 0
    $Queued = if ($QueueId) { " (queue $QueueId)" } else { '' }

    try {
        $Existing = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        Get-CIPPDefenderIndicator -TenantFilter $Domain | & { process {
                if ($_.indicatorType -cne $IndicatorType -or $null -eq $_.indicatorValue) { return }
                $Key = "$($_.indicatorValue)".Trim().ToLowerInvariant()
                if (-not $Seen.Contains($Key)) { return }
                if (-not $Existing.ContainsKey($Key)) { $Existing[$Key] = [System.Collections.Generic.List[object]]::new() }
                $Existing[$Key].Add($_)
            } }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Failed = $Values.Count
        $Results.Add([pscustomobject]@{ resultText = "Nothing was added in $($Domain): CIPP could not read its existing Defender indicators. $($ErrorMessage.NormalizedError)"; state = 'error'; tenant = $Domain })
        Write-LogMessage -headers $Headers -API $APIName -tenant $Domain -tenantId $TenantId -message "Did not add $Action $IndicatorType indicators: the existing indicators could not be read. $($ErrorMessage.NormalizedError)$Queued" -sev Error -LogData $(if ($QueueId) { @{ QueueId = $QueueId; Results = @($Results) } } else { $ErrorMessage })
        return @{ Results = $Results; Failed = $Failed; Conflicts = $Conflicts }
    }

    $ToImport = [System.Collections.Generic.List[string]]::new()
    foreach ($Value in $Values) {
        $Matched = $Existing[$Value]
        $Other = if ($Matched) { @($Matched.Where({ $_.action -cne $Action }).action) }
        if ($Other) {
            $Conflicts++
            $Failed++
            $Results.Add([pscustomobject]@{ resultText = "Skipped $Value in $($Domain): it already exists there as $([System.Collections.Generic.HashSet[string]]::new([string[]]$Other) -join ' and '). Remove it from the Indicators page first to change its action."; state = 'warning'; tenant = $Domain; value = $Value })
        } elseif ($Matched -and $Matched.Where({ @($_.rbacGroupIds).Where({ $null -ne $_ }).Count -gt 0 -or @($_.rbacGroupNames).Where({ $_ }).Count -gt 0 }, 'First').Count -gt 0) {
            $Conflicts++
            $Failed++
            $Results.Add([pscustomobject]@{ resultText = "Skipped $Value in $($Domain): it already exists there for specific device groups, and CIPP leaves it unchanged. Change it in the Microsoft Defender portal."; state = 'warning'; tenant = $Domain; value = $Value })
        } else {
            $ToImport.Add($Value)
        }
    }
    if ($ToImport.Count -eq 0) {
        Write-LogMessage -headers $Headers -API $APIName -tenant $Domain -tenantId $TenantId -message "Added no $Action $IndicatorType indicators: all $($Values.Count) values already exist with another action or for specific device groups$Queued" -sev Warning -LogData $(if ($QueueId) { @{ QueueId = $QueueId; Results = @($Results) } })
        return @{ Results = $Results; Failed = $Failed; Conflicts = $Conflicts }
    }

    try {
        $Body = @{ Indicators = @(foreach ($Value in $ToImport) { $Template + @{ indicatorValue = $Value } }) } | ConvertTo-Json -Compress -Depth 5
        $Body = $Body.Replace('%', '\u0025')
        $Reply = New-GraphPOSTRequest -uri 'https://api.securitycenter.microsoft.com/api/indicators/import' -tenantid $Domain -body $Body -scope 'https://api.securitycenter.microsoft.com/.default' -AsApp $true
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Failed = $Failed + $ToImport.Count
        $Results.Add([pscustomobject]@{ resultText = "Failed to add $($ToImport.Count) indicators in $($Domain): $($ErrorMessage.NormalizedError)"; state = 'error'; tenant = $Domain })
        Write-LogMessage -headers $Headers -API $APIName -tenant $Domain -tenantId $TenantId -message "Failed to add $($ToImport.Count) $Action $IndicatorType indicators: $($ErrorMessage.NormalizedError)$Queued" -sev Error -LogData $(if ($QueueId) { @{ QueueId = $QueueId; Results = @($Results) } } else { $ErrorMessage })
        return @{ Results = $Results; Failed = $Failed; Conflicts = $Conflicts }
    }

    $Replies = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($Item in @($Reply.value)) {
        $Key = "$($Item.indicator)".Trim().ToLowerInvariant()
        if (-not $Replies.ContainsKey($Key)) { $Replies[$Key] = [System.Collections.Generic.List[object]]::new() }
        $Replies[$Key].Add($Item)
    }
    $Written = [System.Collections.Generic.List[string]]::new()
    $TenantFailed = 0
    foreach ($Value in $ToImport) {
        $Item = $Replies[$Value]
        if ($null -eq $Item -or $Item.Count -ne 1 -or $Item[0].isFailed -isnot [bool] -or (-not $Item[0].isFailed -and -not $Item[0].id)) {
            $TenantFailed++
            $Results.Add([pscustomobject]@{ resultText = "Defender did not confirm $Value in $($Domain). Check the Indicators page before adding it again."; state = 'error'; tenant = $Domain; value = $Value })
        } elseif ($Item[0].isFailed) {
            $TenantFailed++
            $Results.Add([pscustomobject]@{ resultText = "Defender refused $Value in $($Domain): $($Item[0].failureReason ?? 'no reason given')"; state = 'error'; tenant = $Domain; value = $Value })
        } else {
            $Written.Add("$($Item[0].id)")
            $Verb = if ($Existing.ContainsKey($Value)) { 'Updated' } else { 'Added' }
            $Results.Add([pscustomobject]@{ resultText = "$Verb $Action indicator $Value in $Domain."; state = 'success'; tenant = $Domain; value = $Value; id = "$($Item[0].id)" })
        }
    }
    $Failed = $Failed + $TenantFailed
    $Message = "Added or updated $($Written.Count) $Action $IndicatorType indicators$(if ($Written.Count) { " (ids $($Written -join ', '))" }), $TenantFailed failed or unconfirmed$(if ($Conflicts) { ", $Conflicts skipped because they already exist with another action or for specific device groups" })$Queued"
    Write-LogMessage -headers $Headers -API $APIName -tenant $Domain -tenantId $TenantId -message $Message -sev $(if ($TenantFailed -or $Conflicts) { 'Warning' } else { 'Info' }) -LogData $(if ($QueueId) { @{ QueueId = $QueueId; Results = @($Results) } })
    return @{ Results = $Results; Failed = $Failed; Conflicts = $Conflicts }
}
