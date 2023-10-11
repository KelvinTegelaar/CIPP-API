using namespace System.Net

function Invoke-ExecUserSettings {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    try {
        $object = $request.body.currentSettings | Select-Object * -ExcludeProperty CurrentTenant, pageSizes, sidebarShow, sidebarUnfoldable, _persist | ConvertTo-Json -Compress
        $Table = Get-CippTable -tablename 'UserSettings'
        $Table.Force = $true
        Add-AzDataTableEntity @Table -Entity @{
            JSON         = "$object"
            RowKey       = "$($Request.body.user)"
            PartitionKey = "UserSettings"
        }
        $StatusCode = [HttpStatusCode]::OK
        $Results = [pscustomobject]@{"Results" = "Successfully added user settings" }
    }
    catch {
        $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
        $Results = "Function Error: $ErrorMsg"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })

}