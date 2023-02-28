using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$Tenantfilter = $request.Query.tenantfilter


$Params = @{
    Identity = $request.query.guid
}

try {
    $cmdlet = if ($request.query.state -eq "enable") { "Enable-TransportRule" } else { "Disable-TransportRule" }
    $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet $cmdlet -cmdParams $params -UseSystemMailbox $true
    $Result = "Set transport rule $($Request.query.guid) to $($request.query.State)"
    Write-LogMessage -API "TransportRules" -tenant $tenantfilter -message "Set transport rule $($Request.query.guid) to $($request.query.State)" -sev Debug
}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception
    $Result = $ErrorMessage
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{Results = $Result }
    })
