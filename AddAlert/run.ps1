using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

$Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
$Results = foreach ($Tenant in $tenants) {
    try {
        $TenantID = if ($tenant -ne 'AllTenants') {
            (get-tenants | Where-Object -Property defaultDomainName -EQ $Tenant).customerId
        }
        else {
            'AllTenants'
        }
        $CompleteObject = @{
            tenant          = $tenant
            tenantid        = $TenantID 
            AdminPassword   = [bool]$Request.body.AdminPassword
            DefenderMalware = [bool]$Request.body.DefenderMalware
            DefenderStatus  = [bool]$Request.body.DefenderStatus
            MFAAdmins       = [bool]$Request.body.MFAAdmins
            MFAAlertUsers   = [bool]$Request.body.MFAAlertUsers
            NewGA           = [bool]$Request.body.NewGA
            NewRole         = [bool]$Request.body.NewRole
            QuotaUsed       = [bool]$Request.body.QuotaUsed
            UnusedLicenses  = [bool]$Request.body.UnusedLicenses
            AppSecretExpiry = [bool]$Request.body.AppSecretExpiry
            NoCAConfig      = [bool]$Request.body.NoCAConfig
            type            = 'Alert'
            RowKey          = $TenantID 
            PartitionKey    = 'Alert'
        }

        $Table = get-cipptable -TableName 'SchedulerConfig'
        <#$TableRow = @{
            table          = ()
            property       = $CompleteObject
            UpdateExisting = $true
        }#>
        Write-Host ($TableRow | ConvertTo-Json)

        #Add-AzTableRow @TableRow | Out-Null
        Add-AzDataTableEntity @Table -Entity $CompleteObject -Force
        "Succesfully added Alert for $($Tenant) to queue."
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Succesfully added Alert for $($Tenant) to queue." -Sev 'Info'
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Failed to add Alert for for $($Tenant) to queue" -Sev 'Error'
        "Failed to add Alert for for $($Tenant) to queue $($_.Exception.message)"
    }
}

$body = [pscustomobject]@{'Results' = @($results) }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
