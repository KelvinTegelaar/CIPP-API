function Get-CIPPBaselineRetentionPolicyTagState {
    <#
    .SYNOPSIS
        Prepare hook for RetentionPolicyTag: the CIPP Deleted Items retention tag and its
        MRM policy link.
    .DESCRIPTION
        Grades the classic's six facts about the fixed 'CIPP Deleted Items' tag: it exists,
        retention is on, the action is PermanentlyDelete, the age limit matches, the type is
        DeletedItems, and the tag is LINKED into the Default MRM Policy - an unlinked tag
        does nothing, which is why the link is graded separately.

        The tenant reports the age limit as a timespan string ('30.00:00:00'); it grades in
        whole days.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Tags = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoRetentionPolicyTags')
    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoRetentionPolicies')
    if ($Tags.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoRetentionPolicyTags')) {
        return @{ Current = $null }
    }

    $TagName = 'CIPP Deleted Items'
    $Tag = $Tags | Where-Object { "$($_.Identity)" -eq $TagName } | Select-Object -First 1
    $MrmPolicy = $Policies | Where-Object { "$($_.Identity)" -eq 'Default MRM Policy' } | Select-Object -First 1

    $CurrentDays = if ($Tag -and $Tag.AgeLimitForRetention) {
        try { [int]([timespan]"$($Tag.AgeLimitForRetention)").TotalDays } catch { -1 }
    } else { -1 }

    $Current = [PSCustomObject]@{
        tagExists        = [bool]$Tag
        retentionEnabled = [bool]($Tag -and $Tag.RetentionEnabled -eq $true)
        retentionAction  = "$($Tag.RetentionAction)"
        ageLimitDays     = [int]$CurrentDays
        tagType          = "$($Tag.Type)"
        linkedToPolicy   = [bool]($MrmPolicy -and @($MrmPolicy.RetentionPolicyTagLinks) -contains $TagName)
    }
    # Carried for the executor: the link write must resend the FULL link list plus ours.
    $Current | Add-Member -NotePropertyName 'existingLinks' -NotePropertyValue @($MrmPolicy.RetentionPolicyTagLinks)

    @{
        Expected = [PSCustomObject]@{
            tagExists        = $true
            retentionEnabled = $true
            retentionAction  = 'PermanentlyDelete'
            ageLimitDays     = [int]"$($Item.Variables.AgeLimitForRetention)"
            tagType          = 'DeletedItems'
            linkedToPolicy   = $true
        }
        Current  = $Current
    }
}
