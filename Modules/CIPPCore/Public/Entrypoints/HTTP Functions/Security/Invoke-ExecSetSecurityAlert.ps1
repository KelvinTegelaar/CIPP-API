using namespace System.Net

Function Invoke-ExecSetSecurityAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $AlertFilter = $Request.Query.GUID ?? $Request.Body.GUID
    $Status = $Request.Query.Status ?? $Request.Body.Status
    $Vendor = $Request.Query.Vendor ?? $Request.Body.Vendor
    $Provider = $Request.Query.Provider ?? $Request.Body.Provider
    $AssignBody = '{"status":"' + $Status + '","vendorInformation":{"provider":"' + $Provider + '","vendor":"' + $Vendor + '"}}'

    try {
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/security/alerts/$AlertFilter" -type PATCH -tenantid $TenantFilter -body $AssignBody
        $Result = "Set alert $AlertFilter to status $Status"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update alert $($AlertFilter): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
