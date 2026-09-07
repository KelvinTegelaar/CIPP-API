Function Invoke-ExecMailboxMobileDevices {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    # Interact with query parameters or the body of the request. This is a state-changing action,
    # so the frontend dispatches it as a POST; keep the query fallback for backwards compatibility.
    $UserId = $Request.Body.Userid ?? $Request.Query.Userid
    $Guid = $Request.Body.guid ?? $Request.Query.guid
    $DeviceId = $Request.Body.deviceid ?? $Request.Query.deviceid
    $Quarantine = $Request.Body.Quarantine ?? $Request.Query.Quarantine
    $Delete = $Request.Body.Delete ?? $Request.Query.Delete
    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    Try {
        $MobileResults = Set-CIPPMobileDevice -UserId $UserId -Guid $Guid -DeviceId $DeviceId -Quarantine $Quarantine -tenantFilter $TenantFilter -APIName $APINAME -Delete $Delete -Headers $Request.Headers
        $Results = [pscustomobject]@{'Results' = $MobileResults }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed  $($UserId): $($_.Exception.Message)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
