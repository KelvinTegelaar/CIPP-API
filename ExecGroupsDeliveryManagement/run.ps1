using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


# Interact with query parameters or the body of the request.
Try {
    $OnlyAllowInternal = if ($request.query.OnlyAllowInternal -eq 'true') { "true" } else { "false" }
    $tenantfilter = $Request.Query.TenantFilter 
    if ($request.query.GroupType -eq "Distribution List" -or $request.query.GroupType -eq "Mail-Enabled Security") {
    New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-DistributionGroup" -cmdParams @{Identity = $request.query.id; RequireSenderAuthenticationEnabled = $OnlyAllowInternal }
    } elseif ($request.query.GroupType -eq "Microsoft 365") {
        New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-UnifiedGroup" -cmdParams @{Identity = $request.query.id; RequireSenderAuthenticationEnabled = $OnlyAllowInternal }
    } elseif ($request.query.GroupType -eq "Security") {
        $Results = [pscustomobject]@{"Results" =  "$($request.query.GroupType)'s group cannot have this setting changed"}
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "This setting cannot be set on a security group." -Sev "Error"
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })
        exit
    }

if ($OnlyAllowInternal -eq "$true") {
    $Results = [pscustomobject]@{"Results" = "Set $($request.query.GroupType) group $($request.query.id) to only allow messages from people inside the organisation."}
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "$($request.query.id) Set to only allow messages from people inside the organisation." -Sev "Info"
}
else {
    $Results = [pscustomobject]@{"Results" = "Set $($request.query.GroupType) group $($request.query.id) to allow messages from people inside and outside the organisation."}
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "$($request.query.id) set to allow messages from people inside and outside the organisation." -Sev "Info"
}     
}
catch {
    $Results = [pscustomobject]@{"Results" = "Failed. $_.Exception.Message" }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Delivery Management failed: $($_.Exception.Message)" -Sev "Error"
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
