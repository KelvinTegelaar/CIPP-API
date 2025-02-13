function New-CIPPIntuneTemplate {
    param(
        $urlname,
        $id,
        $TenantFilter,
        $ActionResults,
        $CIPPURL,
        $ODataType
    )
    Write-Host "These are all bound params: $urlname, $id, $TenantFilter, $ActionResults, $CIPPURL, $ODataType"
    if ($ODataType) {
        switch -wildcard ($ODataType) {
            '*CompliancePolicy' {
                $URLName = 'deviceCompliancePolicies'
            }
            '*managedAppPolicies' {
                $URLName = 'managedAppPolicies'
            }
            '*configurationPolicies' {
                $URLName = 'configurationPolicies'
            }
            '*windowsDriverUpdateProfiles' {
                $URLName = 'windowsDriverUpdateProfiles'
            }
            '*deviceConfigurations' {
                $URLName = 'deviceConfigurations'
            }
            '*groupPolicyConfigurations' {
                $URLName = 'groupPolicyConfigurations'
            }
        }
    }
    switch ($URLName) {
        'deviceCompliancePolicies' {
            $Type = 'deviceCompliancePolicies'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)/$($ID)?`$expand=scheduledActionsForRule(`$expand=scheduledActionConfigurations)" -tenantid $tenantfilter
            $DisplayName = $Template.displayName
            $TemplateJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
        }
        'managedAppPolicies' {
            $Type = 'AppProtection'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/$($urlname)('$($ID)')" -tenantid $tenantfilter
            $DisplayName = $Template.displayName
            $TemplateJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
        }
        'configurationPolicies' {
            $Type = 'Catalog'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)('$($ID)')?`$expand=settings" -tenantid $tenantfilter | Select-Object name, description, settings, platforms, technologies, templateReference
            $TemplateJson = $Template | ConvertTo-Json -Depth 100
            $DisplayName = $Template.name

        }
        'windowsDriverUpdateProfiles' {
            $Type = 'windowsDriverUpdateProfiles'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)/$($ID)" -tenantid $tenantfilter | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
            $DisplayName = $Template.displayName
            $TemplateJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
        }
        'deviceConfigurations' {
            $Type = 'Device'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)/$($ID)" -tenantid $tenantfilter | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
            $DisplayName = $Template.displayName
            $TemplateJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
        }
        'groupPolicyConfigurations' {
            $Type = 'Admin'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)('$($ID)')" -tenantid $tenantfilter
            $DisplayName = $Template.displayName
            $TemplateJsonItems = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)('$($ID)')/definitionValues?`$expand=definition" -tenantid $tenantfilter
            $TemplateJsonSource = foreach ($TemplateJsonItem in $TemplateJsonItems) {
                $presentationValues = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)('$($ID)')/definitionValues('$($TemplateJsonItem.id)')/presentationValues?`$expand=presentation" -tenantid $tenantfilter | ForEach-Object {
                    $obj = $_
                    if ($obj.id) {
                        $PresObj = @{
                            id                        = $obj.id
                            'presentation@odata.bind' = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($TemplateJsonItem.definition.id)')/presentations('$($obj.presentation.id)')"
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


            $TemplateJson = (ConvertTo-Json -InputObject $inputvar -Depth 100 -Compress)
        }
    }
    return [PSCustomObject]@{
        TemplateJson = $TemplateJson
        DisplayName  = $DisplayName
        Description  = $Template.description
        Type         = $Type
    }
}
