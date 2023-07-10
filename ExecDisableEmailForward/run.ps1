using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
try {
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
    $Username = $request.body.user
    $Tenantfilter = $request.body.tenantfilter
    $Results = try {
        $OoO = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-Mailbox" -cmdParams @{Identity = $request.body.user; ForwardingAddress = $null; ForwardingSMTPAddress = $null; DeliverToMailboxAndForward = $false }
        "Disabled Email forwarding $username"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Disabled Email forwarding $($username)" -Sev "Info" -tenant $TenantFilter

    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Could not disable Email forwarding for $($username)" -Sev "Error" -tenant $TenantFilter
        "Could not disable forwarding message for $($username). Error: $($_.Exception.Message)"
    }

    $body = [pscustomobject]@{"Results" = @($results) }
}
catch {
    $body = [pscustomobject]@{"Results" = @("Could not disable forwarding user: $($_.Exception.message)") }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
