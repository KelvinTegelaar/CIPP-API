using namespace System.Net

Function Invoke-ExecEmailForward {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Tenantfilter = $request.body.tenantfilter
    $username = $request.body.userid
    $ForwardingAddress = $request.body.ForwardInternal.value
    $ForwardingSMTPAddress = $request.body.ForwardExternal
    $DisableForwarding = $request.body.disableForwarding
    $APIName = $TriggerMetadata.FunctionName

    if ($ForwardingAddress) {
        try {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-mailbox' -cmdParams @{Identity = $Username; ForwardingAddress = $ForwardingAddress ; DeliverToMailboxAndForward = [bool]$request.body.keepCopy } -Anchor $username
            if (-not $request.body.KeepCopy) {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Set Forwarding for $($username) to $($ForwardingAddress) and not keeping a copy" -Sev 'Info' -tenant $TenantFilter
                $results = "Forwarding all email for $($username) to $($ForwardingAddress) and not keeping a copy"
            } elseif ($request.body.KeepCopy) {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Set Forwarding for $($username) to $($ForwardingAddress) and keeping a copy" -Sev 'Info' -tenant $TenantFilter
                $results = "Forwarding all email for $($username) to $($ForwardingAddress) and keeping a copy"
            }
        } catch {
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Could not add forwarding for $($username)" -Sev 'Error' -tenant $TenantFilter
            $results = "Could not add forwarding for $($username). Error: $($_.Exception.Message)"

        }
    }

    elseif ($ForwardingSMTPAddress) {
        try {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-mailbox' -cmdParams @{Identity = $Username; ForwardingSMTPAddress = $ForwardingSMTPAddress ; DeliverToMailboxAndForward = [bool]$request.body.keepCopy } -Anchor $username
            if (-not $request.body.KeepCopy) {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Set forwarding for $($username) to $($ForwardingSMTPAddress) and not keeping a copy" -Sev 'Info' -tenant $TenantFilter
                $results = "Forwarding all email for $($username) to $($ForwardingSMTPAddress) and not keeping a copy"
            } elseif ($request.body.KeepCopy) {
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Set forwarding for $($username) to $($ForwardingSMTPAddress) and keeping a copy" -Sev 'Info' -tenant $TenantFilter
                $results = "Forwarding all email for $($username) to $($ForwardingSMTPAddress) and keeping a copy"
            }
        } catch {
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Could not add forwarding for $($username)" -Sev 'Error' -tenant $TenantFilter
            $results = "Could not add forwarding for $($username). Error: $($_.Exception.Message)"

        }

    }

    elseif ($DisableForwarding -eq 'True') {
        try {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $Username; ForwardingAddress = $null; ForwardingSMTPAddress = $null; DeliverToMailboxAndForward = $false }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Disabled Email forwarding for $($username)" -Sev 'Info' -tenant $TenantFilter
            $results = "Disabled Email Forwarding for $($username)"
        } catch {
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Could not disable Email forwarding for $($username)" -Sev 'Error' -tenant $TenantFilter
            $results = "Could not disable Email forwarding for $($username). Error: $($_.Exception.Message)"

        }
    }

    $Body = @{'Results' = @($results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
