using namespace System.Net

Function Invoke-ExecHideFromGAL {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Headers = $Request.Headers
    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -Headers $Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Support if the request is a POST or a GET. So to support legacy(GET) and new(POST) requests
    $UserId = $Request.Query.ID ?? $Request.body.ID
    $TenantFilter = $Request.Query.TenantFilter ?? $Request.body.tenantFilter
    $Hidden = -not [string]::IsNullOrWhiteSpace($Request.Query.HideFromGAL) ? [System.Convert]::ToBoolean($Request.Query.HideFromGAL) : [System.Convert]::ToBoolean($Request.body.HideFromGAL)


    Try {
        $HideResults = Set-CIPPHideFromGAL -tenantFilter $TenantFilter -UserID $UserId -hidefromgal $Hidden -Headers $Request.Headers -APIName $APIName
        $Results = [pscustomobject]@{'Results' = $HideResults }
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = [pscustomobject]@{'Results' = "Failed. $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
