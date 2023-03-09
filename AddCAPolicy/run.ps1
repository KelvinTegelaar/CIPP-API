using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
if ("AllTenants" -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }
$displayname = ($request.body.RawJSON | ConvertFrom-Json).Displayname
function Remove-EmptyArrays ($Object) {
    if ($Object -is [Array]) {
        foreach ($Item in $Object) { Remove-EmptyArrays $Item }
    }
    elseif ($Object -is [HashTable]) {
        foreach ($Key in @($Object.get_Keys())) {
            if ($Object[$Key] -is [Array] -and $Object[$Key].get_Count() -eq 0) {
                $Object.Remove($Key)
            }
            else { Remove-EmptyArrays $Object[$Key] }
        }
    }
    elseif ($Object -is [PSCustomObject]) {
        foreach ($Name in @($Object.psobject.properties.Name)) {
            if ($Object.$Name -is [Array] -and $Object.$Name.get_Count() -eq 0) {
                $Object.PSObject.Properties.Remove($Name)
            }
            elseif ($object.$name -eq $null) {
                $Object.PSObject.Properties.Remove($Name)
            }
            else { Remove-EmptyArrays $Object.$Name }
        }
    }
}

$JSONObj = $request.body.RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty ID, GUID, *time*
Remove-EmptyArrays $JSONObj
#Remove context as it does not belong in the payload.
$JsonObj.grantControls.PSObject.Properties.Remove('authenticationStrength@odata.context')
$JsonObj.conditions.users.excludeGuestsOrExternalUsers.externalTenants.PSObject.Properties.Remove('@odata.type')
$RawJSON = $JSONObj | ConvertTo-Json -Depth 10

$results = foreach ($Tenant in $tenants) {
    try {
        $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" -tenantid $tenant
        $PolicyName = ($RawJSON | ConvertFrom-Json).displayName
        if ($PolicyName -in $CheckExististing.displayName) {
            Throw "Conditional Access Policy with Display Name $($Displayname) Already exists"
        }
    
        $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies" -tenantid $tenant -type POST -body $RawJSON
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added Conditional Access Policy $($Displayname)" -Sev "Error"
        "Successfully added Conditional Access Policy for $($Tenant)"
    }
    catch {
        "Failed to add policy for $($Tenant): $($_.Exception.Message)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Failed adding Conditional Access Policy $($Displayname). Error: $($_.Exception.Message)" -Sev "Error"
        continue
    }

}

$body = [pscustomobject]@{"Results" = @($results) }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
