function Invoke-ListUserSettings {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.User.Read
    #>
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers


    $Username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

    try {
        $Table = Get-CippTable -tablename 'UserSettings'
        $UserSettings = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'UserSettings' and RowKey eq 'allUsers'"
        if (!$UserSettings) { $UserSettings = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'UserSettings' and RowKey eq '$Username'" }

        try {
            $UserSettings = $UserSettings.JSON | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Failed to convert UserSettings JSON: $($_.Exception.Message)"
            $UserSettings = [pscustomobject]@{
                direction      = 'ltr'
                paletteMode    = 'light'
                currentTheme   = @{ value = 'light'; label = 'light' }
                pinNav         = $true
                showDevtools   = $false
                customBranding = @{
                    colour = '#F77F00'
                    logo   = $null
                }
            }
        }

        try {
            $UserSpecificSettings = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'UserSettings' and RowKey eq '$Username'"
            $UserSpecificSettings = $UserSpecificSettings.JSON | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "Failed to convert UserSpecificSettings JSON: $($_.Exception.Message)"
        }

        #Get branding settings
        if ($UserSettings) {
            $brandingTable = Get-CippTable -tablename 'Config'
            $BrandingSettings = Get-CIPPAzDataTableEntity @brandingTable -Filter "PartitionKey eq 'BrandingSettings' and RowKey eq 'BrandingSettings'"
            if ($BrandingSettings) {
                $UserSettings | Add-Member -MemberType NoteProperty -Name 'customBranding' -Value $BrandingSettings -Force | Out-Null
            }
        }

        if ($UserSpecificSettings) {
            $UserSettings | Add-Member -MemberType NoteProperty -Name 'UserSpecificSettings' -Value $UserSpecificSettings -Force | Out-Null
        }

        $StatusCode = [HttpStatusCode]::OK
        $Results = $UserSettings
    } catch {
        $Results = "Function Error: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
