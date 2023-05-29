using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
$Table = Get-CIPPTable -TableName SchedulerConfig
$Filter = "RowKey eq 'CippNotifications' and PartitionKey eq 'CippNotifications'"
$Config = [pscustomobject](Get-AzDataTableEntity @Table -Filter $Filter)

$Settings = [System.Collections.ArrayList]@('Alerts')
$Config.psobject.properties.name | ForEach-Object { $settings.add($_) } 
$Table = Get-CIPPTable
$PartitionKey = Get-Date -UFormat '%Y%m%d'
$Filter = "PartitionKey eq '{0}'" -f $PartitionKey
# Interact with query parameters or the body of the request.
$Currentlog = Get-AzDataTableEntity @Table -Filter $Filter | Where-Object { $_.API -In $Settings }
$HTMLLog = ($CurrentLog | Select-Object Message, API, Tenant, Username, Severity | Where-Object -Property tenant -EQ $tenant | ConvertTo-Html -frag) -replace '<table>', '<table class=blueTable>' | Out-String
$Alert = [pscustomobject]@{
    TenantId   = "Test Tenant"
    AlertText  = "<style>table.blueTable{border:1px solid #1C6EA4;background-color:#EEE;width:100%;text-align:left;border-collapse:collapse}table.blueTable td,table.blueTable th{border:1px solid #AAA;padding:3px 2px}table.blueTable tbody td{font-size:13px}table.blueTable tr:nth-child(even){background:#D0E4F5}table.blueTable thead{background:#1C6EA4;background:-moz-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:-webkit-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:linear-gradient(to bottom,#5592bb 0,#327cad 66%,#1C6EA4 100%);border-bottom:2px solid #444}table.blueTable thead th{font-size:15px;font-weight:700;color:#FFF;border-left:2px solid #D0E4F5}table.blueTable thead th:first-child{border-left:none}table.blueTable tfoot{font-size:14px;font-weight:700;color:#FFF;background:#D0E4F5;background:-moz-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:-webkit-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:linear-gradient(to bottom,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);border-top:2px solid #444}table.blueTable tfoot td{font-size:14px}table.blueTable tfoot .links{text-align:right}table.blueTable tfoot .links a{display:inline-block;background:#1C6EA4;color:#FFF;padding:2px 8px;border-radius:5px}</style> $($htmllog)"
    AlertTitle = "CIPP Alert: Alerts found starting at $((Get-Date).AddMinutes(-15))"
}

New-CippExtAlert -Alert $Alert


Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    }) -clobber