using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$GUID = (New-Guid).GUID
try { 
    if ($Request.body.rawJSON) {       
        if (!$Request.body.displayname) { throw "You must enter a displayname" }
        if ($null -eq ($Request.body.Rawjson | ConvertFrom-Json)) { throw "the JSON is invalid" }
        

        $object = [PSCustomObject]@{
            Displayname = $request.body.displayname
            Description = $request.body.description
            RAWJson     = $request.body.RawJSON
            Type        = $request.body.TemplateType
            GUID        = $GUID
        } | ConvertTo-Json
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-AzDataTableEntity @Table -Entity @{
            JSON         = "$object"
            RowKey       = "$GUID"
            PartitionKey = "IntuneTemplate"
        }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Created intune policy template named $($Request.body.displayname) with GUID $GUID" -Sev "Debug"

        $body = [pscustomobject]@{"Results" = "Successfully added template" }
    }
    else {
        $TenantFilter = $request.query.TenantFilter
        $URLName = $Request.query.URLName
        $ID = $request.query.id
        switch ($URLName) {

            "configurationPolicies" {
                $Type = "Catalog"
                $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)('$($ID)')?`$expand=settings" -tenantid $tenantfilter | Select-Object name, description, settings, platforms, technologies
                $TemplateJson = $Template | ConvertTo-Json -Depth 10
                $DisplayName = $template.name


            } 
            "deviceConfigurations" {
                $Type = "Device"
                $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)/$($ID)" -tenantid $tenantfilter | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                Write-Host ($Template | ConvertTo-Json)
                $DisplayName = $template.displayName
                $TemplateJson = ConvertTo-Json -InputObject $Template -Depth 10 -Compress
            }
            "groupPolicyConfigurations" {
                $Type = "Admin"
                $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)('$($ID)')" -tenantid $tenantfilter
                $DisplayName = $Template.displayName
                $TemplateJsonItems = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)('$($ID)')/definitionValues?`$expand=definition" -tenantid $tenantfilter
                $TemplateJsonSource = foreach ($TemplateJsonItem in $TemplateJsonItems) {
                    $presentationValues = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)('$($ID)')/definitionValues('$($TemplateJsonItem.id)')/presentationValues?`$expand=presentation" -tenantid $tenantfilter | ForEach-Object {
                        $obj = $_
                        if ($obj.id) {
                            $PresObj = @{
                                id                        = $obj.id
                                "presentation@odata.bind" = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($TemplateJsonItem.definition.id)')/presentations('$($obj.presentation.id)')"
                            }
                            if ($obj.values) { $PresObj['values'] = $obj.values }
                            if ($obj.value) { $PresObj['value'] = $obj.value }
                            if ($obj.'@odata.type') { $PresObj['@odata.type'] = $obj.'@odata.type' }
                            [pscustomobject]$PresObj
                        }
                    }
                    [PSCustomObject]@{
                        'definition@odata.bind' = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($TemplateJsonItem.definition.id)')"
                        enabled                 = $TemplateJsonItem.enabled
                        presentationValues      = @($presentationValues)
                    }
                }
                $inputvar = [pscustomobject]@{
                    added      = @($TemplateJsonSource)
                    updated    = @()
                    deletedIds = @()

                }
                

                $TemplateJson = (ConvertTo-Json -InputObject $inputvar -Depth 15 -Compress)
            }
        }
       

        $object = [PSCustomObject]@{
            Displayname = $DisplayName
            Description = $Template.Description
            RAWJson     = $TemplateJson
            Type        = $Type
            GUID        = $GUID
        } | ConvertTo-Json
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-AzDataTableEntity @Table -Entity @{
            JSON         = "$object"
            RowKey       = "$GUID"
            PartitionKey = "IntuneTemplate"
        }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Created intune policy template $($Request.body.displayname) with GUID $GUID using an original policy from a tenant" -Sev "Debug"

        $body = [pscustomobject]@{"Results" = "Successfully added template" }
    }
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal'  -API $APINAME -message "Intune Template Deployment failed: $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Intune Template Deployment failed: $($_.Exception.Message)" }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
