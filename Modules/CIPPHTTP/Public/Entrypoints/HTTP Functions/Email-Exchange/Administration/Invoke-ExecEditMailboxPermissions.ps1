function Invoke-ExecEditMailboxPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


    # This endpoint is not called in the frontend at all. This can only be called manually via the scheduler, via the API, or via the CIPPAPIModule -Bobby

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APINAME-message 'Accessed this API' -Sev 'Debug'
    $Username = $request.body.userID
    $Tenantfilter = $request.body.tenantfilter
    if ($username -eq $null) { exit }
    $Results = [System.Collections.ArrayList]@()

    # Each request-body bucket maps to a (PermissionLevel, Action) pair. Delegate to
    # Set-CIPPMailboxPermission so the EXO cmdlet mapping, logging, cache sync, and error handling
    # all live in one place. The mailbox UPN is passed straight through as the identity - EXO accepts
    # it, so no Graph id lookup is required.
    $PermissionBuckets = @(
        @{ Bucket = 'RemoveFullAccess'; PermissionLevel = 'FullAccess'; Action = 'Remove'; AutoMap = $true }
        @{ Bucket = 'AddFullAccess'; PermissionLevel = 'FullAccess'; Action = 'Add'; AutoMap = $true }
        @{ Bucket = 'AddFullAccessNoAutoMap'; PermissionLevel = 'FullAccess'; Action = 'Add'; AutoMap = $false }
        @{ Bucket = 'AddSendAs'; PermissionLevel = 'SendAs'; Action = 'Add'; AutoMap = $true }
        @{ Bucket = 'RemoveSendAs'; PermissionLevel = 'SendAs'; Action = 'Remove'; AutoMap = $true }
        @{ Bucket = 'AddSendOnBehalf'; PermissionLevel = 'SendOnBehalf'; Action = 'Add'; AutoMap = $true }
        @{ Bucket = 'RemoveSendOnBehalf'; PermissionLevel = 'SendOnBehalf'; Action = 'Remove'; AutoMap = $true }
    )

    foreach ($Bucket in $PermissionBuckets) {
        foreach ($AccessUser in ($Request.body.($Bucket.Bucket)).value) {
            $null = $Results.Add(
                (Set-CIPPMailboxPermission -UserId $Username -AccessUser $AccessUser -PermissionLevel $Bucket.PermissionLevel -Action $Bucket.Action -AutoMap $Bucket.AutoMap -TenantFilter $Tenantfilter -APIName $APIName -Headers $Headers)
            )
        }
    }

    $body = [pscustomobject]@{'Results' = @($results) }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
