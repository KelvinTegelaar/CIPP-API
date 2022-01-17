using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$user = $request.headers.'x-ms-client-principal'
$Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
$displayname = $request.body.Displayname
$description = $request.body.Description
$AssignTo = if ($request.body.Assignto -ne "on") { $request.body.Assignto }
$RawJSON = $Request.body.RawJSON

$results = foreach ($Tenant in $tenants) {
    try {
        switch ($Request.body.TemplateType) {
            "Admin" {
                $CreateBody = '{"description":"' + $description + '","displayName":"' + $displayname + '","roleScopeTagIds":["0"]}'
                $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations" -tenantid $tenant -type POST -body $CreateBody
                $UpdateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations('$($CreateRequest.id)')/updateDefinitionValues" -tenantid $tenant -type POST -body $RawJSON
            }
            "Device" {
                $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations" -tenantid $tenant -type POST -body $RawJSON
            }
            "Catalog" {
                $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" -tenantid $tenant -type POST -body $RawJSON
            }

        }
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added policy $($Displayname)" -Sev "Error"
        if ($AssignTo) {
            $AssignBody = if ($AssignTo -ne "AllDevicesAndUsers") { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($AssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
            $assign = New-GraphPOSTRequest -uri  "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations('$($CreateRequest.id)')/assign" -tenantid $tenant -type POST -body $AssignBody
            Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Assigned policy $($Displayname) to $AssignTo" -Sev "Info"
        }
        "Succesfully added policy for $($Tenant)"
    }
    catch {
        "Failed to add policy for $($Tenant): $($_.Exception.Message)"
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Failed adding policy $($Displayname). Error: $($_.Exception.Message)" -Sev "Error"
        continue
    }

}

$body = [pscustomobject]@{"Results" = $results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
