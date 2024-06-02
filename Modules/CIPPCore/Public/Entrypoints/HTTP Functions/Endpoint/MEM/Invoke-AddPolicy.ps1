using namespace System.Net

Function Invoke-AddPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Tenants = ($Request.Body | Select-Object Select_*).psobject.properties.value
    if ('AllTenants' -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }
    $displayname = $Request.Body.displayName
    $description = $Request.Body.Description
    $AssignTo = if ($Request.Body.AssignTo -ne 'on') { $Request.Body.AssignTo }
    $RawJSON = $Request.Body.RAWJson

    $results = foreach ($Tenant in $tenants) {
        if ($Request.Body.replacemap.$tenant) {
        ([pscustomobject]$Request.Body.replacemap.$tenant).psobject.properties | ForEach-Object { $RawJson = $RawJson -replace $_.name, $_.value }
        }
        try {
            switch ($Request.Body.TemplateType) {
                'AppProtection' {
                    $TemplateType = ($RawJSON | ConvertFrom-Json).'@odata.type' -replace '#microsoft.graph.', ''
                    $TemplateTypeURL = "$($TemplateType)s"
                    $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/$TemplateTypeURL" -tenantid $tenant
                    if ($displayname -in $CheckExististing.displayName) {
                        Throw "Policy with Display Name $($Displayname) Already exists"
                    }
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $RawJSON
                }
                'deviceCompliancePolicies' {
                    $TemplateTypeURL = 'deviceCompliancePolicies'
                    $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
                    if ($displayname -in $CheckExististing.displayName) {
                        Throw "Policy with Display Name $($Displayname) Already exists"
                    }
                    $JSON = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, 'scheduledActionsForRule@odata.context', '@odata.context'
                    $JSON.scheduledActionsForRule = @($JSON.scheduledActionsForRule | Select-Object * -ExcludeProperty 'scheduledActionConfigurations@odata.context')
                    $RawJSON = ConvertTo-Json -InputObject $JSON -Depth 20 -Compress
                    Write-Host $RawJSON
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $RawJson
                }
                'Admin' {
                    $TemplateTypeURL = 'groupPolicyConfigurations'
                    $CreateBody = '{"description":"' + $description + '","displayName":"' + $displayname + '","roleScopeTagIds":["0"]}'
                    $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
                    if ($displayname -in $CheckExististing.displayName) {
                        Throw "Policy with Display Name $($Displayname) Already exists"
                    }
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $CreateBody
                    $UpdateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL('$($CreateRequest.id)')/updateDefinitionValues" -tenantid $tenant -type POST -body $RawJSON
                }
                'Device' {
                    $TemplateTypeURL = 'deviceConfigurations'
                    $PolicyName = ($RawJSON | ConvertFrom-Json).displayName
                    $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
                    Write-Host $PolicyName
                    if ($PolicyName -in $CheckExististing.displayName) {
                        Throw "Policy with Display Name $($Displayname) Already exists"
                    }
                    $PolicyFile = $RawJSON | ConvertFrom-Json
                    $Null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'description' -Value $description -Force
                    $null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'displayName' -Value $displayname -Force
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 20
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $RawJSON
                }
                'Catalog' {
                    $TemplateTypeURL = 'configurationPolicies'
                    $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
                    $PolicyName = ($RawJSON | ConvertFrom-Json).Name
                    $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
                    if ($PolicyName -in $CheckExististing.name) {
                        Throw "Policy with Display Name $($Displayname) Already exists"
                    }
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $RawJSON
                }

            }
            Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added policy $($Displayname)" -Sev 'Info'
            if ($AssignTo) {
                Set-CIPPAssignedPolicy -GroupName $AssignTo -PolicyId $CreateRequest.id -Type $TemplateTypeURL -TenantFilter $tenant
            }
            "Successfully added policy for $($Tenant)"
        } catch {
            "Failed to add policy for $($Tenant): $($_.Exception.Message)"
            Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Failed adding policy $($Displayname). Error: $($_.Exception.Message)" -Sev 'Error'
            continue
        }

    }

    $body = [pscustomobject]@{'Results' = @($results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
