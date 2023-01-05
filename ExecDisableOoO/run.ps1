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
        $OoO = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-MailboxAutoReplyConfiguration" -cmdParams @{Identity = $userid; AutoReplyState = "Disabled" }
        "Disabled Out-of-office for $username"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Disable Out-of-office for $($username)" -Sev "Info" -tenant $TenantFilter

    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Could not disable OOO for $($username)" -Sev "Error" -tenant $TenantFilter
        "Could not disable out of office message for $($username). Error: $($_.Exception.Message)"
    }

    $body = [pscustomobject]@{"Results" = @($results) }
}
catch {
    $body = [pscustomobject]@{"Results" = @("Could not disable Out of Office user: $($_.Exception.message)") }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
