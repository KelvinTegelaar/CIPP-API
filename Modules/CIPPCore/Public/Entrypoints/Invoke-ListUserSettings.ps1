using namespace System.Net

function Invoke-ListUserSettings {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

    try {
        $Table = Get-CippTable -tablename 'UserSettings'
        $UserSettings = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'allUsers'"
        if (!$UserSettings) { Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$username'" }
        $UserSettings = $UserSettings | Select-Object -ExpandProperty JSON | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
        $StatusCode = [HttpStatusCode]::OK
        $Results = $UserSettings
    }
    catch {
        $Results = "Function Error: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}