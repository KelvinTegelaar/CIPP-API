using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$RequestParams = $Request.Body.PowerShellCommand | ConvertFrom-Json | Select-Object -Property * -ExcludeProperty GUID, Comments

$Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
$Result = foreach ($Tenantfilter in $tenants) {
    $Existing = New-ExoRequest -ErrorAction SilentlyContinue -tenantid $Tenantfilter -cmdlet "Get-TransportRule" -useSystemMailbox $true | Where-Object -Property Identity -EQ $RequestParams.name
    try {
        if ($Existing) {
            Write-Host "Found existing"
            $RequestParams | Add-Member -NotePropertyValue $RequestParams.name -NotePropertyName Identity
            $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet "Set-TransportRule" -cmdParams ($RequestParams | Select-Object -Property * -ExcludeProperty UseLegacyRegex) -useSystemMailbox $true
            "Successfully set transport rule for $tenantfilter."
        }
        else {
            Write-Host "Creating new"
            $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet "New-TransportRule" -cmdParams $RequestParams -useSystemMailbox $true
            "Successfully created transport rule for $tenantfilter."
        }
        
        Write-LogMessage -API $APINAME -tenant $tenantfilter -message "Created transport rule for $($tenantfilter)" -sev Debug
    }
    catch {
        "Could not create transport rule for $($tenantfilter): $($_.Exception.message)"
    }
}
 

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{Results = @($Result) }
    })
