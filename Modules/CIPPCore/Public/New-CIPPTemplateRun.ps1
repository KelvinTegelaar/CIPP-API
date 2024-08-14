function New-CIPPTemplateRun {
    [CmdletBinding()]
    param (
        $TemplateSettings,
        $TenantFilter
    )
    $Table = Get-CippTable -tablename 'templates'
    $ExistingTemplates = (Get-CIPPAzDataTableEntity @Table) | ForEach-Object {
        $data = $_.JSON | ConvertFrom-Json -Depth 100
        $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.RowKey -Force
        $data | Add-Member -NotePropertyName 'PartitionKey' -NotePropertyValue $_.PartitionKey -Force
        $data
    } | Sort-Object -Property displayName


    $Tasks = foreach ($key in $TemplateSettings.Keys) {
        if ($TemplateSettings[$key] -eq $true) {
            $key
        }
    }


    foreach ($Task in $Tasks) {
        Write-Host "Working on task $Task"
        switch ($Task) {
            'ca' {
                Write-Host "Template Conditional Access Policies for $TenantFilter"
                $Policies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/policies?$top=999' -tenantid $TenantFilter
                Write-Host 'Creating templates for found Conditional Access Policies'
                foreach ($policy in $policies) {
                    try {
                        $Template = New-CIPPCATemplate -TenantFilter $TenantFilter -JSON $policy
                        #check existing templates, if the displayName is the same, overwrite it.
                        $ExistingPolicy = $ExistingTemplates | Where-Object { $_.displayName -eq $policy.displayName } | Select-Object -First 1
                        if ($ExistingPolicy -and $ExistingPolicy.PartitionKey -eq 'CATemplate') {
                            "Policy $($policy.displayName) found, updating template"
                            Add-CIPPAzDataTableEntity @Table -Entity @{
                                JSON         = "$Template"
                                RowKey       = $ExistingPolicy.GUID
                                PartitionKey = 'CATemplate'
                                GUID         = $ExistingPolicy.GUID
                            } -Force
                        } else {
                            "Policy $($policy.displayName) not found in existing templates, creating new template"
                            $GUID = (New-Guid).GUID
                            Add-CIPPAzDataTableEntity @Table -Entity @{
                                JSON         = "$Template"
                                RowKey       = "$GUID"
                                PartitionKey = 'CATemplate'
                                GUID         = "$GUID"
                            }
                        }

                    } catch {
                        "Failed to create a template of the Conditional Access Policy with ID: $($policy.id). Error: $($_.Exception.Message)"
                    }
                }
            }
            'intuneconfig' {
                Write-Host "Backup Intune Configuration Policies for $TenantFilter"
                $GraphURLS = @("https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$select=id,displayName,lastModifiedDateTime,roleScopeTagIds,microsoft.graph.unsupportedDeviceConfiguration/originalEntityTypeName&`$expand=assignments&top=1000"
                    'https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles'
                    "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?`$expand=assignments&top=999"
                    "https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations?`$expand=assignments&`$filter=microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig%20eq%20true"
                    'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
                )

                $Policies = foreach ($url in $GraphURLS) {
                    try {
                        $Policies = New-GraphGetRequest -uri "$($url)" -tenantid $TenantFilter
                        $URLName = (($url).split('?') | Select-Object -First 1) -replace 'https://graph.microsoft.com/beta/deviceManagement/', ''
                        foreach ($Policy in $Policies) {
                            try {
                                $Template = New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName $URLName -ID $Policy.ID
                                $ExistingPolicy = $ExistingTemplates | Where-Object { $_.displayName -eq $Template.DisplayName } | Select-Object -First 1
                                if ($ExistingPolicy -and $ExistingPolicy.PartitionKey -eq 'IntuneTemplate') {
                                    "Policy $($Template.DisplayName) found, updating template"
                                    $object = [PSCustomObject]@{
                                        Displayname = $Template.DisplayName
                                        Description = $Template.Description
                                        RAWJson     = $Template.TemplateJson
                                        Type        = $Template.Type
                                        GUID        = $ExistingPolicy.GUID
                                    } | ConvertTo-Json

                                    Add-CIPPAzDataTableEntity @Table -Entity @{
                                        JSON         = "$object"
                                        RowKey       = $ExistingPolicy.GUID
                                        PartitionKey = 'IntuneTemplate'
                                    } -Force
                                } else {
                                    "Policy  $($Template.DisplayName) not found in existing templates, creating new template"
                                    $GUID = (New-Guid).GUID
                                    $object = [PSCustomObject]@{
                                        Displayname = $Template.DisplayName
                                        Description = $Template.Description
                                        RAWJson     = $Template.TemplateJson
                                        Type        = $Template.Type
                                        GUID        = $GUID
                                    } | ConvertTo-Json

                                    Add-CIPPAzDataTableEntity @Table -Entity @{
                                        JSON         = "$object"
                                        RowKey       = "$GUID"
                                        PartitionKey = 'IntuneTemplate'
                                    } -Force
                                }
                            } catch {
                                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                                "Failed to create a template of the Intune Configuration Policy with ID: $($Policy.id). Error: $ErrorMessage"
                            }
                        }
                    } catch {
                        Write-Host "Failed to backup $url"
                    }
                }
            }
            'intunecompliance' {
                Write-Host "Backup Intune Compliance Policies for $TenantFilter"
                New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?$top=999' -tenantid $TenantFilter | ForEach-Object {
                    $Template = New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName 'deviceCompliancePolicies' -ID $_.ID
                    $ExistingPolicy = $ExistingTemplates | Where-Object { $_.displayName -eq $Template.DisplayName } | Select-Object -First 1
                    if ($ExistingPolicy -and $ExistingPolicy.PartitionKey -eq 'IntuneTemplate') {
                        "Policy $($Template.DisplayName) found, updating template"
                        $object = [PSCustomObject]@{
                            Displayname = $Template.DisplayName
                            Description = $Template.Description
                            RAWJson     = $Template.TemplateJson
                            Type        = $Template.Type
                            GUID        = $ExistingPolicy.GUID
                        } | ConvertTo-Json

                        Add-CIPPAzDataTableEntity @Table -Entity @{
                            JSON         = "$object"
                            RowKey       = $ExistingPolicy.GUID
                            PartitionKey = 'IntuneTemplate'
                        } -Force
                    } else {
                        "Policy  $($Template.DisplayName) not found in existing templates, creating new template"
                        $GUID = (New-Guid).GUID
                        $object = [PSCustomObject]@{
                            Displayname = $Template.DisplayName
                            Description = $Template.Description
                            RAWJson     = $Template.TemplateJson
                            Type        = $Template.Type
                            GUID        = $GUID
                        } | ConvertTo-Json

                        Add-CIPPAzDataTableEntity @Table -Entity @{
                            JSON         = "$object"
                            RowKey       = "$GUID"
                            PartitionKey = 'IntuneTemplate'
                        } -Force
                    }

                }
            }

            'intuneprotection' {
                Write-Host "Backup Intune Protection Policies for $TenantFilter"
                New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/managedAppPolicies?$top=999' -tenantid $TenantFilter | ForEach-Object {
                    $Template = New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName 'managedAppPolicies' -ID $_.ID
                    $ExistingPolicy = $ExistingTemplates | Where-Object { $_.displayName -eq $Template.DisplayName } | Select-Object -First 1
                    if ($ExistingPolicy -and $ExistingPolicy.PartitionKey -eq 'IntuneTemplate') {
                        "Policy $($Template.DisplayName) found, updating template"
                        $object = [PSCustomObject]@{
                            Displayname = $Template.DisplayName
                            Description = $Template.Description
                            RAWJson     = $Template.TemplateJson
                            Type        = $Template.Type
                            GUID        = $ExistingPolicy.GUID
                        } | ConvertTo-Json

                        Add-CIPPAzDataTableEntity @Table -Entity @{
                            JSON         = "$object"
                            RowKey       = $ExistingPolicy.GUID
                            PartitionKey = 'IntuneTemplate'
                        } -Force
                    } else {
                        "Policy  $($Template.DisplayName) not found in existing templates, creating new template"
                        $GUID = (New-Guid).GUID
                        $object = [PSCustomObject]@{
                            Displayname = $Template.DisplayName
                            Description = $Template.Description
                            RAWJson     = $Template.TemplateJson
                            Type        = $Template.Type
                            GUID        = $GUID
                        } | ConvertTo-Json

                        Add-CIPPAzDataTableEntity @Table -Entity @{
                            JSON         = "$object"
                            RowKey       = "$GUID"
                            PartitionKey = 'IntuneTemplate'
                        } -Force
                    }
                }
            }

        }
    }
    return $BackupData
}

