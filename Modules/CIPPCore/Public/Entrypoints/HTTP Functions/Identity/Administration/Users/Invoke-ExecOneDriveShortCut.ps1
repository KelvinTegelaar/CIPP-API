using namespace System.Net

Function Invoke-ExecOneDriveShortCut {
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

    # Interact with the body of the request
    $TenantFilter = $Request.Body.tenantFilter
    $Username = $Request.Body.username
    $UserId = $Request.Body.userid
    $URL = $Request.Body.siteUrl.value

    Try {
        $Result = New-CIPPOneDriveShortCut -Username $Username -UserId $UserId -TenantFilter $TenantFilter -URL $URL -Headers $Headers
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
