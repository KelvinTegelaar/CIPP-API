Function Invoke-ExecHideFromGAL {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers



    # Support if the request is a POST or a GET. So to support legacy(GET) and new(POST) requests
    $UserId = $Request.Query.ID ?? $Request.body.ID
    $TenantFilter = $Request.Query.TenantFilter ?? $Request.body.tenantFilter
    $HideFromGAL = $Request.Query.HideFromGAL ?? $Request.body.HideFromGAL
    $HideFromGAL = [System.Convert]::ToBoolean($HideFromGAL)

    Try {
        $Result = Set-CIPPHideFromGAL -tenantFilter $TenantFilter -UserID $UserId -hidefromgal $HideFromGAL -Headers $Headers -APIName $APIName
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })

}
