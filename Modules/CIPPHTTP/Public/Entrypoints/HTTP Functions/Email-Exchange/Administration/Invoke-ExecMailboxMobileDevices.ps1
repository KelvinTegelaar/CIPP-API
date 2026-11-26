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
    # Issue an account-only wipe: removes the Exchange account data from the device, not the whole device.
    $Wipe = $Request.Body.Wipe
    # Cancel an account-only wipe that the device has not yet carried out.
    $CancelWipe = $Request.Body.CancelWipe
    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    Try {
        $MobileResults = Set-CIPPMobileDevice -UserId $UserId -Guid $Guid -DeviceId $DeviceId -Quarantine $Quarantine -tenantFilter $TenantFilter -APIName $APINAME -Delete $Delete -Wipe $Wipe -CancelWipe $CancelWipe -Headers $Request.Headers
        $Results = [pscustomobject]@{'Results' = $MobileResults }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = [pscustomobject]@{'Results' = $_.Exception.Message }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
