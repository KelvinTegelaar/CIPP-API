using namespace System.Net

Function Invoke-ExecCreateTAP {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $UserID = $Request.Query.ID ?? $Request.Body.ID

    try {
        $TAPResult = New-CIPPTAP -userid $UserID -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers

        # Create results array with both TAP and UserID as separate items
        $Results = @(
            $TAPResult,
            @{
                resultText = "User ID: $UserID"
                copyField = $UserID
                state = 'success'
            }
        )

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = Get-NormalizedError -message $($_.Exception.Message)
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Results }
        })

}
