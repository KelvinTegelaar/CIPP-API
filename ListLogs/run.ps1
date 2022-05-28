using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Info'

if ($request.Query.SearchNow -eq 'True') {
    $LogLevel = ($Request.query.Severity).split(',') 
    #$date = $Request.query.DateFilter
    $PartitionKey = $Request.query.DateFilter
    $username = $Request.Query.User
}
else {
    $LogLevel = 'Info', 'Warn', 'Error', 'Critical', 'Alert'
    #$date = (Get-Date).ToString('ddMMyyyy')
    $PartitionKey = Get-Date -UFormat '%Y%m%d'
    $username = '*'
}
$context = New-AzStorageContext -ConnectionString $ENV:AzureWebJobsStorage
$tablename = 'CippLogs'
try { 
    $StorageTable = Get-AzStorageTable –Context $context -Name $tablename -ErrorAction Stop
}
catch {
    New-AzStorageTable -Context $context -Name $tablename | Out-Null
    $StorageTable = Get-AzStorageTable –Context $context -Name $tablename
}
    
$Table = $StorageTable.CloudTable

#$IllegalLines = New-Object -TypeName 'System.Collections.ArrayList'

$ReturnedLog = if ($Request.Query.ListLogs) {
    #Get-ChildItem 'Logs' | Select-Object Name, BaseName | ForEach-Object { @{
    #        value = $_.BaseName
    #        label = $_.BaseName
    #    } }
    Get-AzTableRow -Table $table | Sort-Object -Unique partitionkey | ForEach-Object {
        @{ 
            value = $_.PartitionKey
            label = $_.PartitionKey
        }
    }
}
else {
    $Rows = Get-AzTableRow -Table $table -PartitionKey $PartitionKey | Where-Object { $_.Severity -In $LogLevel -and $_.user -like $username }
    foreach ($Row in $Rows) {
        @{
            DateTime = $Row.TableTimeStamp
            Tenant   = $Row.Tenant
            API      = $Row.API
            Message  = $Row.Message
            User     = $Row.Username
            Severity = $Row.Severity
        }
    }

    <#$content = Get-Content "Logs\$($date).log"
    foreach ($line in $content) {
        try {
            $line | ConvertFrom-Csv -Header 'DateTime', 'Tenant', 'API', 'Message', 'User', 'Severity' -Delimiter '|' -ErrorAction Stop | Where-Object { $_.Severity -In $LogLevel -and $_.user -like $username 
            } 
        }
        catch {
            Write-Host $content.IndexOf($line)
            $IllegalLines.Add($content.IndexOf($line))
        }
    }#>
}
#if ($IllegalLines.count -ge 1) { Log-Request "The following line numbers in the log are invalid: $IllegalLines" -API $APINAME -Sev Warn }

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($ReturnedLog)
    })
