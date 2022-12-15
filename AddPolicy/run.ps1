using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
if ("AllTenants" -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }
$displayname = $request.body.Displayname
$description = $request.body.Description
$AssignTo = if ($request.body.Assignto -ne "on") { $request.body.Assignto }
$RawJSON = $Request.body.RawJSON

$results = foreach ($Tenant in $tenants) {
    if ($Request.body.replacemap.$tenant) {
        ([pscustomobject]$Request.body.replacemap.$tenant).psobject.properties | ForEach-Object { $RawJson = $RawJson -replace $_.name, $_.value }
    }
    try {
        switch ($Request.body.TemplateType) {
            "Admin" {
                $TemplateTypeURL = "groupPolicyConfigurations"
                $CreateBody = '{"description":"' + $description + '","displayName":"' + $displayname + '","roleScopeTagIds":["0"]}'
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
                if ($displayname -in $CheckExististing.displayName) {
                    Throw "Policy with Display Name $($Displayname) Already exists"
                }
                $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $CreateBody
                $UpdateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL('$($CreateRequest.id)')/updateDefinitionValues" -tenantid $tenant -type POST -body $RawJSON
            }
            "Device" {
                $TemplateTypeURL = "deviceConfigurations"
                $PolicyName = ($RawJSON | ConvertFrom-Json).displayName
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
                Write-Host $PolicyName
                if ($PolicyName -in $CheckExististing.displayName) {
                    Throw "Policy with Display Name $($Displayname) Already exists"
                }
                
                $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $RawJSON
            }
            "Catalog" {
                $TemplateTypeURL = "configurationPolicies"
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
                $PolicyName = ($RawJSON | ConvertFrom-Json).Name
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
                if ($PolicyName -in $CheckExististing.name) {
                    Throw "Policy with Display Name $($Displayname) Already exists"
                }
                $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $RawJSON
            }

        }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added policy $($Displayname)" -Sev "Error"
        if ($AssignTo) {
            $AssignBody = if ($AssignTo -ne "AllDevicesAndUsers") { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($AssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
            $assign = New-GraphPOSTRequest -uri  "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL('$($CreateRequest.id)')/assign" -tenantid $tenant -type POST -body $AssignBody
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Assigned policy $($Displayname) to $AssignTo" -Sev "Info"
        }
        "Successfully added policy for $($Tenant)"
    }
    catch {
        "Failed to add policy for $($Tenant): $($_.Exception.Message)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Failed adding policy $($Displayname). Error: $($_.Exception.Message)" -Sev "Error"
        continue
    }

}

$body = [pscustomobject]@{"Results" = @($results) }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
