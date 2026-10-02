function Invoke-ExecPushSubscription {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.ReadWrite
    .DESCRIPTION
        Registers, removes or tests a Web Push subscription for the signed-in user's device.
        Subscriptions are per user: the row belongs to the principal that sent it and only that
        principal can remove it. Refused while impersonating, so a superadmin trying a role never
        binds their own device to a browser session that is pretending to be someone else.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    $Action = [string]$Request.Body.Action

    try {
        if (![string]::IsNullOrWhiteSpace($Headers.'x-cipp-impersonate-role')) {
            throw 'Push notification devices cannot be changed while impersonating a role.'
        }

        $Table = Get-CIPPTable -tablename 'PushSubscriptions'
        switch ($Action) {
            'Subscribe' {
                $Subscription = $Request.Body.Subscription
                $Endpoint = [string]$Subscription.endpoint
                if (![string]::IsNullOrWhiteSpace($Endpoint) -and -not $Endpoint.StartsWith('https://')) { $Endpoint = '' }
                if ([string]::IsNullOrWhiteSpace($Endpoint) -or [string]::IsNullOrWhiteSpace($Subscription.keys.p256dh) -or [string]::IsNullOrWhiteSpace($Subscription.keys.auth)) {
                    throw 'A push subscription needs an https endpoint and p256dh/auth keys.'
                }
                $RowKey = Get-StringHash -String $Endpoint
                $DeviceName = [string]$Request.Body.DeviceName
                if ([string]::IsNullOrWhiteSpace($DeviceName)) { $DeviceName = 'Unnamed device' }
                Add-CIPPAzDataTableEntity @Table -Force -Entity @{
                    PartitionKey = $Username
                    RowKey       = $RowKey
                    Endpoint     = $Endpoint
                    P256dh       = [string]$Subscription.keys.p256dh
                    Auth         = [string]$Subscription.keys.auth
                    DeviceName   = $DeviceName.Substring(0, [Math]::Min($DeviceName.Length, 100))
                } | Out-Null
                Write-LogMessage -headers $Headers -API $APIName -message "Registered push notification device '$DeviceName'" -Sev 'Info'
                $Results = @{ Results = "Registered '$DeviceName' for push notifications."; RowKey = $RowKey }
            }
            'Unsubscribe' {
                $RowKey = [string]$Request.Body.RowKey
                $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$Username' and RowKey eq '$RowKey'"
                if (!$Existing) { throw 'That device is not registered to you.' }
                Remove-AzDataTableEntity @Table -Entity $Existing -Force | Out-Null
                Write-LogMessage -headers $Headers -API $APIName -message "Removed push notification device '$($Existing.DeviceName)'" -Sev 'Info'
                $Results = @{ Results = "Removed '$($Existing.DeviceName)'." }
            }
            'Test' {
                $Outcome = Send-CIPPAlert -Type 'push' -TargetUser $Username -Title 'CIPP test notification' -PushMessage 'Push notifications are working on this device.' -Url '/cipp/preferences' -APIName $APIName
                $Results = @{ Results = "$Outcome" }
            }
            default { throw "Unknown action '$Action'. Use Subscribe, Unsubscribe or Test." }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = @{ Results = "$($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
