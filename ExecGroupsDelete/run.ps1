using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


# Interact with query parameters or the body of the request.
Try {
    $tenantfilter = $Request.Query.TenantFilter
    if ($request.query.GroupType -eq "Distribution List" -or $request.query.GroupType -eq "Mail-Enabled Security") {
        New-ExoRequest -tenantid $TenantFilter -cmdlet "Remove-DistributionGroup" -cmdParams @{Identity = $request.query.id; BypassSecurityGroupManagerCheck = $true }
        $Results = [pscustomobject]@{"Results" = "Successfully Deleted $($request.query.GroupType) group $($request.query.DisplayName)" }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "$($request.query.DisplayName) Deleted" -Sev "Info"
    
    }
    elseif ($request.query.GroupType -eq "Microsoft 365" -or $request.query.GroupType -eq "Security") {
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/groups/$($Request.query.ID)" -tenantid $TenantFilter -type Delete -verbose
    
        $Results = [pscustomobject]@{"Results" = "Successfully Deleted $($request.query.GroupType) group $($request.query.DisplayName)" }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "$($request.query.DisplayName) Deleted" -Sev "Info"
    }
}
catch {
    $Results = [pscustomobject]@{"Results" = "Failed. $($_.Exception.Message)" }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Delete Group Failed: $($_.Exception.Message)" -Sev "Error"
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
