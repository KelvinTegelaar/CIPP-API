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
    New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-mailbox" -cmdParams @{Identity = $request.query.id; HiddenFromAddressListsEnabled = $Hidden }

    $Results = [pscustomobject]@{}

if ($Hidden -eq "$true") {
    $Results | Add-Member -Type NoteProperty -Name "Results" -Value "Successfully hidden $($request.query.id) from GAL."
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "$($request.query.id) Hidden from GAL" -Sev "Info"
}
else {
    $Results | Add-Member -Type NoteProperty -Name "Results" -Value "Successfully unhidden $($request.query.id) from GAL."
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "$($request.query.id) Unhidden from GAL" -Sev "Info"
}     
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Hide/UnHide from GAL failed: $($_.Exception.Message)" -Sev "Error"
    $Results = [pscustomobject]@{"Results" = "Failed. $_.Exception.Message" }
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
