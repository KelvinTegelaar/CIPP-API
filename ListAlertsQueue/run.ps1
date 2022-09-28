using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
$Table = Get-CIPPTable -TableName 'SchedulerConfig' 
$Filter = "PartitionKey eq 'Alert'"
$QueuedApps = Get-AzDataTableEntity @Table -Filter $Filter

$CurrentStandards = foreach ($QueueFile in $QueuedApps) {
    [PSCustomObject]@{
        tenantName      = $QueueFile.tenant
        AdminPassword   = [bool]$QueueFile.AdminPassword
        DefenderMalware = [bool]$QueueFile.DefenderMalware
        DefenderStatus  = [bool]$QueueFile.DefenderStatus
        MFAAdmins       = [bool]$QueueFile.MFAAdmins
        MFAAlertUsers   = [bool]$QueueFile.MFAAlertUsers
        NewGA           = [bool]$QueueFile.NewGA
        NewRole         = [bool]$QueueFile.NewRole
        QuotaUsed       = [bool]$QueueFile.QuotaUsed
        UnusedLicenses  = [bool]$QueueFile.UnusedLicenses
        AppSecretExpiry = [bool]$QueueFile.AppSecretExpiry
        ApnCertExpiry   = [bool]$QueueFile.ApnCertExpiry
        VppTokenExpiry  = [bool]$QueueFile.VppTokenExpiry
        DepTokenExpiry  = [bool]$QueueFile.DepTokenExpiry
        NoCAConfig      = [bool]$QueueFile.NoCAConfig
        tenantId        = $QueueFile.tenantid
    }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($CurrentStandards)
    })
