using namespace System.Net

function Invoke-AddEnrollment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Input bindings are passed in via param block.
    $Tenants = $Request.Body.selectedTenants.value
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

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{'Results' = $Results }
        })

}
