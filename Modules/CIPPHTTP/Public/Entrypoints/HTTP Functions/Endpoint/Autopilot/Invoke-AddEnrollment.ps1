function Invoke-AddEnrollment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Input bindings are passed in via param block.
    $Tenants = $Request.Body.selectedTenants.value

    # Tenant scope: a scoped role must not reach tenants outside its allowed set through selectedTenants.
    $AllowedTenants = Test-CippAccess -Request $Request -TenantList
    if ($AllowedTenants -ne 'AllTenants') {
        $AllowedTenantList = (Get-Tenants -IncludeErrors) | Where-Object { $_.customerId -in $AllowedTenants }
        $Tenants = $Tenants | Where-Object { $_ -in $AllowedTenantList.defaultDomainName }
    }

    $Profbod = $Request.Body
    $Results = foreach ($Tenant in $Tenants) {
        $ParamSplat = @{
            TenantFilter          = $Tenant
            ShowProgress          = $Profbod.ShowProgress
            BlockDevice           = $Profbod.blockDevice
            AllowReset            = $Profbod.AllowReset
            EnableLog             = $Profbod.EnableLog
            ErrorMessage          = $Profbod.ErrorMessage
            TimeOutInMinutes      = $Profbod.TimeOutInMinutes
            AllowFail             = $Profbod.AllowFail
            OBEEOnly              = $Profbod.OBEEOnly
            InstallWindowsUpdates = $Profbod.InstallWindowsUpdates
        }
        Set-CIPPDefaultAPEnrollment @ParamSplat
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{'Results' = $Results }
        })

}
