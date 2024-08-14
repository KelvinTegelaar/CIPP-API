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
    [bool]$KeepCopy = if ($request.body.keepCopy -eq 'true') { $true } else { $false }

    if ($ForwardingAddress) {
        try {
            Set-CIPPForwarding -userid $username -tenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal' -Forward $ForwardingAddress -keepCopy $KeepCopy
            if (-not $request.body.KeepCopy) {
                $results = "Forwarding all email for $($username) to $($ForwardingAddress) and not keeping a copy"
            } else {
                $results = "Forwarding all email for $($username) to $($ForwardingAddress) and keeping a copy"
            }
        } catch {
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Could not add forwarding for $($username)" -Sev 'Error' -tenant $TenantFilter
            $results = "Could not add forwarding for $($username). Error: $($_.Exception.Message)"

        }
    }

    if ($ForwardingSMTPAddress) {
        try {
            Set-CIPPForwarding -userid $username -tenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal' -forwardingSMTPAddress $ForwardingSMTPAddress -keepCopy $KeepCopy
            if (-not $request.body.KeepCopy) {
                $results = "Forwarding all email for $($username) to $($ForwardingSMTPAddress) and not keeping a copy"
            } else {
                $results = "Forwarding all email for $($username) to $($ForwardingSMTPAddress) and keeping a copy"
            }
        } catch {
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Could not add forwarding for $($username)" -Sev 'Error' -tenant $TenantFilter
            $results = "Could not add forwarding for $($username). Error: $($_.Exception.Message)"

        }

    }

    if ($DisableForwarding -eq 'True') {
        try {
            Set-CIPPForwarding -userid $username -username $username -tenantFilter $Tenantfilter -ExecutingUser $ExecutingUser -APIName $APIName -Disable $true
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
