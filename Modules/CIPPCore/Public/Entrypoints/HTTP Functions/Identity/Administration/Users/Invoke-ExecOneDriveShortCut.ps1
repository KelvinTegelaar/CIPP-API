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

    Try {
        $Result = New-CIPPOneDriveShortCut -username $Request.Body.username -userid $Request.Body.userid -TenantFilter $Request.Body.tenantFilter -URL $Request.Body.siteUrl.value -Headers $Request.Headers
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
