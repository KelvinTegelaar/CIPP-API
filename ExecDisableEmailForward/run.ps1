using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
try {
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
    $Username = $request.body.user
    $Tenantfilter = $request.body.tenantfilter
    $message = $Request.body.input
    $userid = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($username)" -tenantid $Tenantfilter).id
    $Results = try {
        $OoO = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-Mailbox" -cmdParams @{Identity = $userid; ForwardingAddress = $null; ForwardingSMTPAddress = $null }
        "Disabled Email forwarding $username"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Disabled Email forwarding $($username)" -Sev "Info" -tenant $TenantFilter

    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Could not disable Email forwarding for $($username)" -Sev "Error" -tenant $TenantFilter
        "Could not disable out of office message for $($username). Error: $($_.Exception.Message)"
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
