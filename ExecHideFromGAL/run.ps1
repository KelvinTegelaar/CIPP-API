using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


$TenantFilter = $request.query.tenantfilter
Try {
    $Hidden = [System.Convert]::ToBoolean($Request.query.HideFromGal)
    $HideResults = Set-CIPPHideFromGAL -tenantFilter $tenantFilter -userid $Request.query.ID -HideFromGAL $Hidden -ExecutingUser $request.headers.'x-ms-client-principal' -APIName "ExecOffboardUser"
    $Results = [pscustomobject]@{"Results" = $HideResults }

}
catch {
    $Results = [pscustomobject]@{"Results" = "Failed. $($_.Exception.Message)" }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Hide/UnHide from GAL failed: $($_.Exception.Message)" -Sev "Error"
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
