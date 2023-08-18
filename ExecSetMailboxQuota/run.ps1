using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
try {
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
    $Username = $request.body.user
    $Tenantfilter = $request.body.tenantfilter
    $quota = $Request.body.input
    $Results = try {
        if ($Request.Body.ProhibitSendQuota) {
            $quota = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-Mailbox" -cmdParams @{Identity = $Username; ProhibitSendQuota = $quota }
            "Changed ProhibitSendQuota for $username - $($message)"
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message  "Changed ProhibitSendQuota for $username - $($message)" -Sev "Info" -tenant $TenantFilter
        }
        if ($Request.Body.ProhibitSendReceiveQuota) {
            $quota = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-Mailbox" -cmdParams @{Identity = $Username; ProhibitSendReceiveQuota = $quota }
            "Changed ProhibitSendReceiveQuota for $username - $($message)"
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message  "Changed ProhibitSendReceiveQuota for $username - $($message)" -Sev "Info" -tenant $TenantFilter
        }
        if ($Request.Body.IssueWarningQuota) {
            $quota = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-Mailbox" -cmdParams @{Identity = $Username; IssueWarningQuota = $quota }
            "Changed IssueWarningQuota for $username - $($message)"
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message  "Changed IssueWarningQuota for $username - $($message)" -Sev "Info" -tenant $TenantFilter
        }
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Could not add OOO for $($username)" -Sev "Error" -tenant $TenantFilter
        "Could not add out of office message for $($username). Error: $($_.Exception.Message)"
    }

    $body = [pscustomobject]@{"Results" = @($results) }
}
catch {
    $body = [pscustomobject]@{"Results" = @("Could not set Out of Office user: $($_.Exception.message)") }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
