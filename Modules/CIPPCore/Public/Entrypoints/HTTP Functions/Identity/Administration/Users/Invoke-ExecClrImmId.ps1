using namespace System.Net

Function Invoke-ExecClrImmId {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    Write-LogMessage -headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev Debug
    $UserID = $Request.Query.ID ?? $Request.Body.ID

    Try {
        $Result = Clear-CIPPImmutableId -userid $UserID -TenantFilter $TenantFilter -Headers $Request.Headers -APIName $APIName
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = $ErrorMessage.NormalizedError
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    $Results = [pscustomobject]@{'Results' = $Result }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
