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
    $ForwardOption = $request.body.forwardOption
    $APIName = $Request.Params.CIPPEndpoint
    [bool]$KeepCopy = if ($request.body.keepCopy -eq 'true') { $true } else { $false }

    if ($ForwardOption -eq 'internalAddress') {
        try {
            Set-CIPPForwarding -userid $username -tenantFilter $TenantFilter -APIName $APINAME -Headers $Request.Headers -Forward $ForwardingAddress -keepCopy $KeepCopy
            if (-not $request.body.KeepCopy) {
                $results = "Forwarding all email for $($username) to $($ForwardingAddress) and not keeping a copy"
            } else {
                $results = "Forwarding all email for $($username) to $($ForwardingAddress) and keeping a copy"
            }
        } catch {
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Could not add forwarding for $($username)" -Sev 'Error' -tenant $TenantFilter
            $results = "Could not add forwarding for $($username). Error: $($_.Exception.Message)"

        }
    }

    if ($ForwardOption -eq 'ExternalAddress') {
        try {
            Set-CIPPForwarding -userid $username -tenantFilter $TenantFilter -APIName $APINAME -Headers $Request.Headers -forwardingSMTPAddress $ForwardingSMTPAddress -keepCopy $KeepCopy
            if (-not $request.body.KeepCopy) {
                $results = "Forwarding all email for $($username) to $($ForwardingSMTPAddress) and not keeping a copy"
            } else {
                $results = "Forwarding all email for $($username) to $($ForwardingSMTPAddress) and keeping a copy"
            }
        } catch {
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Could not add forwarding for $($username)" -Sev 'Error' -tenant $TenantFilter
            $results = "Could not add forwarding for $($username). Error: $($_.Exception.Message)"

        }

    }

    if ($ForwardOption -eq 'disabled') {
        try {
            Set-CIPPForwarding -userid $username -username $username -tenantFilter $Tenantfilter -Headers $Request.Headers -APIName $APIName -Disable $true
            $results = "Disabled Email Forwarding for $($username)"
        } catch {
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Could not disable Email forwarding for $($username)" -Sev 'Error' -tenant $TenantFilter
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
