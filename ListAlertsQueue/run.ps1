using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

$QueuedApps = Get-ChildItem "Cache_Scheduler\*.alert.json"

$CurrentStandards = foreach ($QueueFile in $QueuedApps) {
    $ApplicationFile = Get-Content "$($QueueFile)" | ConvertFrom-Json
    if ($ApplicationFile.Tenant -eq $null) { continue }
    [PSCustomObject]@{
        tenantName      = $ApplicationFile.tenant
        AdminPassword   = [bool]$ApplicationFile.AdminPassword
        DefenderMalware = [bool]$ApplicationFile.DefenderMalware
        DefenderStatus  = [bool]$ApplicationFile.DefenderStatus
        MFAAdmins       = [bool]$ApplicationFile.MFAAdmins
        MFAAlertUsers   = [bool]$ApplicationFile.MFAAlertUsers
        NewGA           = [bool]$ApplicationFile.NewGA
        NewRole         = [bool]$ApplicationFile.NewRole
        QuotaUsed       = [bool]$ApplicationFile.QuotaUsed
        UnusedLicenses  = [bool]$ApplicationFile.UnusedLicenses
    }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($CurrentStandards)
    })
