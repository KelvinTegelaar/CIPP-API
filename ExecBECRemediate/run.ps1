using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
Write-Host "PowerShell HTTP trigger function processed a request."

$TenantFilter = $request.body.tenantfilter
$SuspectUser = $request.body.userid
$username = $request.body.username
Write-Host $TenantFilter
Write-Host $SuspectUser
$Results = try {
    Set-CIPPResetPassword -userid $username -tenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal'
    Set-CIPPSignInState -userid $username -AccountEnabled $false -tenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal'
    Revoke-CIPPSessions -userid $SuspectUser -username $request.body.username -ExecutingUser $request.headers.'x-ms-client-principal' -APIName $APINAME -tenantFilter $TenantFilter
    $RuleDisabled = 0
    New-ExoRequest -anchor $username -tenantid $TenantFilter -cmdlet "get-inboxrule" -cmdParams @{Mailbox = $username } | ForEach-Object {
        $null = New-ExoRequest -anchor $username -tenantid $TenantFilter -cmdlet "Disable-InboxRule" -cmdParams @{Confirm = $false; Identity = $_.Identity }
        "Disabled Inbox Rule $($_.Identity) for $username" 
        $RuleDisabled ++
    } 
    if ($RuleDisabled) {
        "Disabled $RuleDisabled Inbox Rules for $username"
    }
    else {
        "No Inbox Rules found for $username. We have not disabled any rules."
    }

    Write-LogMessage -API "BECRemediate" -tenant $tenantfilter -message "Executed Remediation for $SuspectUser" -sev "Info"

}
catch {
    #Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to assign app $($appFilter): $($_.Exception.Message)" -Sev "Error"
    $results = [pscustomobject]@{"Results" = "Failed to execute remediation. $($_.Exception.Message)" }
    Write-LogMessage -API "BECRemediate" -tenant $tenantfilter -message "Executed Remediation for $SuspectUser failed" -sev "Error"
}
$results = [pscustomobject]@{"Results" = @($Results) }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
