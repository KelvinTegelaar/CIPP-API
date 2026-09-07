function Invoke-AddScriptedAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.ReadWrite
    .DESCRIPTION
        Creates or updates a scripted CIPP alert, stored as a hidden scheduled task.

        A selection of two or more tenants or groups is stored verbatim and expanded on every run,
        so tenant group membership is always current.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # The tenants, tenant groups or *All Tenants the alert applies to. At least one is required.
    if ($Request.Body.tenantFilter -is [array] -and @($Request.Body.tenantFilter).Count -eq 1) {
        $Request.Body | Add-Member -MemberType NoteProperty -Name 'tenantFilter' -Value $Request.Body.tenantFilter[0] -Force
    }

    if ($Request.Body.tenantFilter -is [array] -and @($Request.Body.tenantFilter).Count -gt 1) {
        $Request.Body | Add-Member -MemberType NoteProperty -Name 'Tenants' -Value @($Request.Body.tenantFilter) -Force

        # Tenant stays 'AllTenants' - the execution gates gate on that literal; Tenants holds the real scope.
        $Request.Body | Add-Member -MemberType NoteProperty -Name 'tenantFilter' -Value ([PSCustomObject]@{
                value = 'AllTenants'
                label = '*All Tenants'
                type  = 'Tenant'
            }) -Force
    }

    # Tenants or tenant groups to skip even when they fall within the selection above. Optional.
    if ($Request.Body.excludedTenants) {
        # Add-CIPPScheduledTask drops entries with no value, so wrap bare domain strings.
        $NormalizedExclusions = @(@($Request.Body.excludedTenants) | Where-Object { $_ } | ForEach-Object {
                if ($_.value) { $_ } else { [PSCustomObject]@{ value = [string]$_; label = [string]$_; type = 'Tenant' } }
            })
        $Request.Body | Add-Member -MemberType NoteProperty -Name 'excludedTenants' -Value $NormalizedExclusions -Force
    }

    $ForwardRequest = @{
        Query   = @{ hidden = 'true' }
        Body    = $Request.Body
        Headers = $Request.Headers
    }

    return Invoke-AddScheduledItem -Request $ForwardRequest -TriggerMetadata $TriggerMetadata
}
