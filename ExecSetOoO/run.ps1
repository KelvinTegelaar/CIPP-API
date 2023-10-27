using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
try {
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
    $Username = $request.body.user
    $Tenantfilter = $request.body.tenantfilter
    if ($Request.body.input) {
        $InternalMessage = $Request.body.input
        $ExternalMessage = $Request.body.input
    }
    else {
        $InternalMessage = $Request.body.InternalMessage
        $ExternalMessage = $Request.body.ExternalMessage
    }
    $StartTime = $Request.body.StartTime
    $EndTime = $Request.body.EndTime
    
    $Results = try {
        if ($Request.Body.AutoReplyState -ne "Scheduled") {
            Set-CIPPOutOfOffice -userid $Request.body.user -tenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal' -InternalMessage $InternalMessage -ExternalMessage $ExternalMessage -State $Request.Body.AutoReplyState
        }
        else {
            Set-CIPPOutOfOffice -userid $Request.body.user -tenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal' -InternalMessage $InternalMessage -ExternalMessage $ExternalMessage -StartTime $StartTime -EndTime $EndTime -State $Request.Body.AutoReplyState
        }
    }
    catch {
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
