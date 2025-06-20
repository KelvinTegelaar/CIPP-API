using namespace System.Net

Function Invoke-ExecUpdateSecureScore {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.TenantFilter
    $ControlName = $Request.Body.ControlName
    $Body = @{
        comment           = $Request.Body.reason
        state             = $Request.Body.resolutionType.value
        vendorInformation = $Request.Body.vendorInformation
    }
    try {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/security/secureScoreControlProfiles/$ControlName" -tenantid $TenantFilter -type PATCH -Body (ConvertTo-Json -InputObject $Body -Compress)
        $StatusCode = [HttpStatusCode]::OK
        $Result = "Successfully set control $ControlName to $($Body.state)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to set control $ControlName to $($Body.state). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
