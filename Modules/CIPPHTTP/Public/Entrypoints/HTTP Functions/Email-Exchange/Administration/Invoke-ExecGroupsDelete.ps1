Function Invoke-ExecGroupsDelete {
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


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $GroupType = $Request.Query.GroupType ?? $Request.Body.GroupType
    $ID = $Request.Query.id ?? $Request.Body.id
    $DisplayName = $Request.Query.displayName ?? $Request.Body.displayName

    Try {
        $Result = Remove-CIPPGroup -ID $ID -GroupType $GroupType -TenantFilter $TenantFilter -DisplayName $DisplayName -APIName $APIName -Headers $Headers
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "$($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
