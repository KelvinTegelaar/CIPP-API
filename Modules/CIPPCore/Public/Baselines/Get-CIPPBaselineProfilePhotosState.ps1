function Get-CIPPBaselineProfilePhotosState {
    <#
    .SYNOPSIS
        Prepare hook for ProfilePhotos: whether users can change their profile photos.
    .DESCRIPTION
        Two surfaces must agree, exactly as the classic graded them: the Graph photo update
        settings (an EMPTY allowedRoles list means users may change photos; disabled means
        the Global admin and User admin role ids are on the list) and the default OWA
        mailbox policy's SetPhotoEnabled flag. One surface enabled while the other is off
        leaves users a working side door, which is why both grade.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $PhotoSettings = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'PhotoUpdateSettings') | Select-Object -First 1
    $OwaPolicies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'OwaMailboxPolicy')
    if (-not $PhotoSettings -and $OwaPolicies.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'PhotoUpdateSettings')) {
        return @{ Current = $null }
    }
    $OwaPolicy = @($OwaPolicies | Where-Object { "$($_.Identity)" -eq 'OwaMailboxPolicy-Default' }) | Select-Object -First 1

    $StateValue = "$($Item.Variables.state.value ?? $Item.Variables.state)"
    if ($StateValue -notin @('enabled', 'disabled')) { return @{ Current = $null } }
    $Desired = $StateValue -eq 'enabled'

    $UsersCanChange = [string]::IsNullOrWhiteSpace("$($PhotoSettings.allowedRoles)")
    $GraphCorrect = $UsersCanChange -eq $Desired
    if (-not $UsersCanChange -and -not $Desired) {
        $GraphCorrect = (@($PhotoSettings.allowedRoles) -contains '62e90394-69f5-4237-9190-012177145e10') -and
        (@($PhotoSettings.allowedRoles) -contains 'fe930be7-5e62-47db-91af-98c3a49a38b1')
    }

    $Current = [PSCustomObject]@{
        photoUpdatePolicyCorrect = [bool]$GraphCorrect
        owaSetPhotoEnabled       = [bool]$OwaPolicy.SetPhotoEnabled
    }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'owaPolicyIdentity' -NotePropertyValue "$($OwaPolicy.Identity ?? 'OwaMailboxPolicy-Default')"

    @{
        Expected = [PSCustomObject]@{ photoUpdatePolicyCorrect = $true; owaSetPhotoEnabled = $Desired }
        Current  = $Current
    }
}
