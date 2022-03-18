using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
$Results = foreach ($Tenant in $tenants) {
    try {
        $CompleteObject = [PSCustomObject]@{
            tenant          = $tenant
            tenantid        = (get-tenants | Where-Object -Property defaultDomainName -EQ $Tenant).Customerid
            AdminPassword   = [bool]$Request.body.AdminPassword
            DefenderMalware = [bool]$Request.body.DefenderMalware
            DefenderStatus  = [bool]$Request.body.DefenderStatus
            MFAAdmins       = [bool]$Request.body.MFAAdmins
            MFAAlertUsers   = [bool]$Request.body.MFAAlertUsers
            NewGA           = [bool]$Request.body.NewGA
            NewRole         = [bool]$Request.body.NewRole
            QuotaUsed       = [bool]$Request.body.QuotaUsed
            UnusedLicenses  = [bool]$Request.body.UnusedLicenses
            Type            = "Alert"

        } | ConvertTo-Json
        $JSONFile = New-Item -Path ".\Cache_Scheduler\$tenant.alert.json" -Value $CompleteObject -Force -ErrorAction Stop
        "Succesfully added Alert for $($Tenant) to queue."
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message  "Succesfully added Alert for $($Tenant) to queue." -Sev "Info"
    }
    catch {
        Log-Request -user $request.headers.'x-ms-client-principal'  -API $APINAME -tenant $tenant -message  "Failed to add Alert for for $($Tenant) to queue" -Sev "Error"
        "Failed to add Alert for for $($Tenant) to queue"
    }
}

$body = [pscustomobject]@{"Results" = @($results) }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
