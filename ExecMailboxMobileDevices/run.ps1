using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


# Interact with query parameters or the body of the request.
Try {
    $Quarantine = if ($request.query.quarantine -eq 'false') { "false" } elseif ($request.query.quarantine -eq 'true' ) {"true"} else { "undefined" }
    $tenantfilter = $Request.Query.TenantFilter 
    if ($Quarantine -eq "false") {
    New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-CASMailbox" -cmdParams @{Identity = $request.query.Userid; ActiveSyncAllowedDeviceIDs = @{'@odata.type' = '#Exchange.GenericHashTable'; add=$request.query.deviceid} }
    $Results = [pscustomobject]@{"Results" = "Allowed Active Sync Device for $($request.query.Userid)"}
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Allow Active Sync Device for $($request.query.Userid)" -Sev "Info"
}
    elseif ($Quarantine -eq "true") {
        New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-CASMailbox" -cmdParams @{Identity = $request.query.Userid; ActiveSyncBlockedDeviceIDs = @{'@odata.type' = '#Exchange.GenericHashTable'; add=$request.query.deviceid} }
        $Results = [pscustomobject]@{"Results" = "Blocked Active Sync Device for $($request.query.Userid)"}
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Blocked Active Sync Device for $($request.query.Userid)" -Sev "Info"
    }
}

catch {
    if ($request.query.quarantine -eq 'false') {
    $Results = [pscustomobject]@{"Results" = "Failed to Allow Active Sync Device for $($request.query.Userid): $_.Exception.Message" }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to Allow Active Sync Device for $($request.query.Userid): $($_.Exception.Message)" -Sev "Error"
    } 
    elseif ($request.query.quarantine -eq 'true') {
        $Results = [pscustomobject]@{"Results" = "Failed to Block Active Sync Device for $($request.query.Userid): $_.Exception.Message" }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to Block Active Sync Device for $($request.query.Userid): $($_.Exception.Message)" -Sev "Error"    
    }
}

try {
if ($request.query.delete -eq 'true') {
    New-ExoRequest -tenant $TenantFilter -cmdlet "Remove-MobileDevice" -cmdParams @{Identity = "$($request.query.Guid)"; Confirm = $false} -UseSystemMailbox $true 
    $Results = [pscustomobject]@{"Results" = "Deleted Active Sync Device for $($request.query.Userid)"}
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Deleted Active Sync Device for $($request.query.Userid)" -Sev "Info"
}
}

catch {
    $Results = [pscustomobject]@{"Results" = "Failed to delete Mobile Device $($request.query.identity) $_.Exception.Message" }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to delete Mobile Device $($request.query.identity): $($_.Exception.Message)" -Sev "Error"
}



# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
