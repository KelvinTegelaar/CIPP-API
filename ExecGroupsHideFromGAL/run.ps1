using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."


# Interact with query parameters or the body of the request.
Try {
    $Hidden = if ($request.query.HidefromGAL -eq 'true') { "true" } else { "false" }
    $tenantfilter = $Request.Query.TenantFilter 
    if ($request.query.GroupType -eq "Distribution List" -or $request.query.GroupType -eq "Mail-Enabled Security") {
    New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-DistributionGroup" -cmdParams @{Identity = $request.query.id; HiddenFromAddressListsEnabled = $Hidden }
    } elseif ($request.query.GroupType -eq "Microsoft 365") {
        New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-UnifiedGroup" -cmdParams @{Identity = $request.query.id; HiddenFromAddressListsEnabled = $Hidden }
    } elseif ($request.query.GroupType -eq "Security") {
        $Results = [pscustomobject]@{"Results" =  "$($request.query.GroupType)'s group cannot have this setting changed"}
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "This setting cannot be set on a security group." -Sev "Error"
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })
        exit
    }

if ($Hidden -eq "$true") {
    $Results = [pscustomobject]@{"Results" = "Successfully hidden $($request.query.GroupType) group $($request.query.id) from GAL."}
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "$($request.query.id) Hidden from GAL" -Sev "Info"
}
else {
    $Results = [pscustomobject]@{"Results" = "Successfully unhidden $($request.query.GroupType) group $($request.query.id) from GAL."}
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "$($request.query.id) Unhidden from GAL" -Sev "Info"
}     
}
catch {
    $Results = [pscustomobject]@{"Results" = "Failed. $_.Exception.Message" }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Hide/UnHide from GAL failed: $($_.Exception.Message)" -Sev "Error"
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
