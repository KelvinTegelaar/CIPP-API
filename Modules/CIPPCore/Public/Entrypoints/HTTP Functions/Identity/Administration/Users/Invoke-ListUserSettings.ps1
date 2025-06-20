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
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

    try {
        $Table = Get-CippTable -tablename 'UserSettings'
        $UserSettings = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq 'allUsers'"
        if (!$UserSettings) { $UserSettings = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$Username'" }
        $UserSettings = $UserSettings.JSON | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
        #Get branding settings
        if ($UserSettings) {
            $brandingTable = Get-CippTable -tablename 'Config'
            $BrandingSettings = Get-CIPPAzDataTableEntity @brandingTable -Filter "RowKey eq 'BrandingSettings'"
            if ($BrandingSettings) {
                $UserSettings | Add-Member -MemberType NoteProperty -Name 'BrandingSettings' -Value $BrandingSettings -Force | Out-Null
            }
        }
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
