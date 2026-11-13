function Invoke-CippTestZTNA41040 {
    <#
    .SYNOPSIS
    Tenant Allow/Block List allow entries are reviewed for expiration, justification, and staleness
    #>
    param($Tenant)

    $TestId = 'ZTNA41040'
    $Name = 'Tenant Allow/Block List allow entries are reviewed for expiration, justification, and staleness'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Exchange -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Exchange Online.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        $Entries = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoTenantAllowBlockList').Where({ $null -ne $_ })
        if ($Entries.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoTenantAllowBlockList' -CountsOnly)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'The Tenant Allow/Block List has not been collected for this tenant. Refresh the ExoTenantAllowBlockList cache.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
            return
        }

        $Now = Get-Date
        $StaleThreshold = $Now.AddDays(-90)
        $ListTypePriority = @{ 'FileHash' = 1; 'Url' = 2; 'Sender' = 3; 'IP' = 4 }
        $AllAllow = $Entries.Where({ $_.Action -eq 'Allow' })
        $BlockCount = $Entries.Where({ $_.Action -eq 'Block' }).Count
        $ExemptCount = $AllAllow.Where({ $_.ListSubType -in @('AdvancedDelivery', 'Submission') }).Count

        $Classified = @(foreach ($Entry in $AllAllow.Where({ $_.ListSubType -eq 'Tenant' })) {
                $Expiration = if ($Entry.ExpirationDate) { [datetime]$Entry.ExpirationDate }
                $LastModified = if ($Entry.LastModifiedDateTime) { [datetime]$Entry.LastModifiedDateTime }
                $IsUnbounded = $null -eq $Expiration
                $HasNotes = -not [string]::IsNullOrWhiteSpace([string]$Entry.Notes)
                $IsActive = $IsUnbounded -or $Expiration -gt $Now
                $IsStale = $IsActive -and $null -ne $LastModified -and $LastModified -lt $StaleThreshold
                [pscustomobject]@{
                    ListType     = $Entry.ListType
                    Value        = [string]$Entry.Value
                    Action       = $Entry.Action
                    Expiration   = $Expiration
                    LastModified = $LastModified
                    Notes        = $Entry.Notes
                    IsUnbounded  = $IsUnbounded
                    IsStale      = $IsStale
                    IsFailEntry  = $IsUnbounded -and -not $HasNotes
                    IsFlagged    = $IsUnbounded -or $IsStale
                    Flags        = @(if ($IsUnbounded) { 'unbounded' }; if (-not $HasNotes) { 'no-notes' }; if ($IsStale) { 'stale' }) -join ', '
                }
            })

        $UnboundedCount = $Classified.Where({ $_.IsUnbounded }).Count
        $UndocumentedCount = $Classified.Where({ $_.IsFailEntry }).Count
        $StaleCount = $Classified.Where({ $_.IsStale }).Count
        $UnboundedRatio = if ($Classified.Count -gt 0) { "$([math]::Round($UnboundedCount / $Classified.Count * 100, 1))%" } else { '—' }

        if ($UndocumentedCount -gt 0) {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("❌ One or more admin-controlled allow entries are unbounded and have no documented business justification in the Notes field. Each is a permanent filter bypass with no recorded reason for its existence. A threat actor who reuses an allowed sender, registers a lookalike under an allowed domain, or replays an allowed file hash will bypass Microsoft's spam, bulk, and phishing verdicts for as long as the entry remains.")
        } elseif ($StaleCount -gt 0 -or $UnboundedCount -gt 0) {
            $Status = 'Investigate'
            $Result = [System.Text.StringBuilder]::new("⚠️ Unbounded allow entries exist but all have populated Notes, or stale entries (not modified in more than 90 days) exist. The customer is using the Tenant Allow/Block List responsibly but should confirm that each unbounded entry's business justification is still current and prune any entries that no longer apply.")
        } else {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new('✅ All admin-controlled allow entries in the Tenant Allow/Block List are either time-bounded or have a documented business justification, and no entry has been left untouched for more than 90 days.')
        }

        $null = $Result.Append("`n`n## [Tenant Allow/Block Lists](https://security.microsoft.com/tenantAllowBlockList) — drift summary`n`n")
        $null = $Result.Append("| Metric | Value | Target |`n")
        $null = $Result.Append("| :----- | ----: | :----- |`n")
        $null = $Result.Append("| Unbounded admin-controlled allow entries | $(if ($UnboundedCount -gt 0) { "⚠️ $UnboundedCount" } else { '0' }) | 0 |`n")
        $null = $Result.Append("| Unbounded entries lacking documented justification | $(if ($UndocumentedCount -gt 0) { "❌ $UndocumentedCount" } else { '0' }) | 0 |`n")
        $null = $Result.Append("| Stale allow entries (last modified >90 days) | $(if ($StaleCount -gt 0) { "⚠️ $StaleCount" } else { '0' }) | 0 |`n")
        $null = $Result.Append("| Unbounded ratio | $UnboundedRatio | <5% (informational) |`n")
        $null = $Result.Append("| Total allow entries (all categories) | $($AllAllow.Count) | — |`n")
        $null = $Result.Append("| Total block entries (not evaluated) | $BlockCount | — |`n")
        $null = $Result.Append("| Excluded entries (AdvancedDelivery + Submission) | $ExemptCount | — |`n")
        $null = $Result.Append("`nExcluded entries (AdvancedDelivery, Submission) are represented by the excluded count row above and never affect the verdict.`n")

        $Flagged = $Classified.Where({ $_.IsFlagged })
        if ($Status -ne 'Passed' -and $Flagged.Count -gt 0) {
            $Sorted = @($Flagged | Sort-Object @{ Expression = { if ($_.IsFailEntry) { 0 } else { 1 } } }, LastModified, @{ Expression = { $ListTypePriority[[string]$_.ListType] } }, @{ Expression = { if ($_.IsStale) { 0 } else { 1 } } }, Value)
            $null = $Result.Append("`n## Action required`n`n")
            $null = $Result.Append("| List type | Value | Action | Expiration date | Last modified | Notes | Flags |`n")
            $null = $Result.Append("| :-------- | :---- | :----- | :-------------- | :------------ | :---- | :----- |`n")
            foreach ($Row in $Sorted.Where({ $true }, 'First', 10)) {
                $Value = $Row.Value -replace '[\r\n]+', ' '
                if ($Value.Length -gt 50) { $Value = $Value.Substring(0, 47) + '...' }
                $Notes = ([string]$Row.Notes).Trim() -replace '[\r\n]+', ' '
                $Notes = if ([string]::IsNullOrWhiteSpace($Notes)) { '—' } elseif ($Notes.Length -gt 80) { ConvertTo-CippMarkdownCell ($Notes.Substring(0, 77) + '...') } else { ConvertTo-CippMarkdownCell $Notes }
                $Expiration = if ($Row.IsUnbounded) { 'No expiration' } else { $Row.Expiration.ToString('yyyy-MM-dd') }
                $LastModified = if ($Row.LastModified) { $Row.LastModified.ToString('yyyy-MM-dd') } else { '—' }
                $null = $Result.Append("| $($Row.ListType) | $(ConvertTo-CippMarkdownCell $Value) | $($Row.Action) | $Expiration | $LastModified | $Notes | $($Row.Flags) |`n")
            }
            if ($Sorted.Count -gt 10) {
                $null = $Result.Append("| ... | ... | ... | ... | ... | ... | ... |`n`n[Microsoft Defender portal > Tenant Allow/Block Lists](https://security.microsoft.com/tenantAllowBlockList)`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result.ToString() -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email and collaboration security'
    }
}
