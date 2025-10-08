function Invoke-ExecUpdateSecureScore {
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


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.TenantFilter
    $ControlName = $Request.Body.ControlName

    if ($ControlName -match '^scid_') {
        $Result = 'Defender controls cannot be updated via this API. Please use the Microsoft 365 Defender portal to update these controls.'
        $StatusCode = [HttpStatusCode]::BadRequest
    } else {
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
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
