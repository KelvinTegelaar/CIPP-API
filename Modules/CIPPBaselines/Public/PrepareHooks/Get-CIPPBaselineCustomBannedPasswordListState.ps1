function Get-CIPPBaselineCustomBannedPasswordListState {
    <#
    .SYNOPSIS
        Prepare hook for CustomBannedPasswordList: are the configured banned words active.
    .DESCRIPTION
        ADDITIVE, like the classic: grades which configured words are missing from the
        tenant's banned password list (tab-separated inside the directory setting) plus
        whether the check is enabled at all. Words on the tenant list that the baseline
        never mentioned are left alone - the remediation merges, capped at Entra's 1000.

        Words outside the 4-16 character bounds Entra enforces are dropped from the grade
        the way the classic dropped them from the write - grading an unwritable word would
        be permanent drift.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Settings = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Settings')
    if ($Settings.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'Settings')) {
        return @{ Current = $null }
    }

    $Words = @("$($Item.Variables.BannedWords)" -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } |
            Where-Object { $_.Length -ge 4 -and $_.Length -le 16 } | Select-Object -Unique)
    if ($Words.Count -eq 0 -or $Words.Count -gt 1000) { return @{ Current = $null } }

    $Existing = @($Settings | Where-Object { "$($_.templateId)" -eq '5cf42378-d67d-4f36-ba46-e8b86229381d' }) | Select-Object -First 1
    $CurrentWords = @()
    if ($Existing) {
        $CurrentWords = @("$((@($Existing.values) | Where-Object { $_.name -eq 'BannedPasswordList' }).value)" -split ([char]9) | Where-Object { $_ })
    }
    $CheckEnabled = [bool]($Existing -and "$((@($Existing.values) | Where-Object { $_.name -eq 'EnableBannedPasswordCheck' }).value)" -eq 'True')
    $Missing = @($Words | Where-Object { $CurrentWords -notcontains $_ } | Sort-Object)

    $Current = [PSCustomObject]@{
        bannedPasswordCheckEnabled = $CheckEnabled
        missingBannedWords         = @($Missing)
    }
    # Carried for the executor: the merge needs the tenant's current words.
    $Current | Add-Member -NotePropertyName 'settingId' -NotePropertyValue "$($Existing.id)"
    $Current | Add-Member -NotePropertyName 'currentWords' -NotePropertyValue @($CurrentWords)

    @{
        Expected = [PSCustomObject]@{ bannedPasswordCheckEnabled = $true; missingBannedWords = @() }
        Current  = $Current
    }
}
