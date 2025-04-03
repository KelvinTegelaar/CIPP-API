using namespace System.Net

function Invoke-ListUserSettings {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.User.Read
    #>
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

    try {
        $Table = Get-CippTable -tablename 'UserSettings'
        $UserSettings = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'allUsers'"
        if (!$UserSettings) { $userSettings = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$username'" }
        $UserSettings = $UserSettings.JSON | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
        $StatusCode = [HttpStatusCode]::OK
        $Results = $UserSettings
    } catch {
        $Results = "Function Error: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
