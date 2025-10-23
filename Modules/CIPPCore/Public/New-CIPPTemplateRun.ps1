function New-CIPPTemplateRun {
    [CmdletBinding()]
    param (
        $TemplateSettings,
        $TenantFilter
    )
    $Table = Get-CippTable -tablename 'templates'
    $ExistingTemplates = (Get-CIPPAzDataTableEntity @Table) | ForEach-Object {
        try {
            $data = $_.JSON | ConvertFrom-Json -ErrorAction SilentlyContinue -Depth 100
            $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.RowKey -Force -ErrorAction Stop
            $data | Add-Member -NotePropertyName 'PartitionKey' -NotePropertyValue $_.PartitionKey -Force -ErrorAction Stop
            $data | Add-Member -NotePropertyName 'SHA' -NotePropertyValue $_.SHA -Force -ErrorAction Stop
            $data
        } catch {
            return
        }
    } | Sort-Object -Property displayName

    function Get-SanitizedFilename {
        param (
            [string]$filename
        )
        $filename = $filename -replace '\s', '_' -replace '[^\w\d_]', ''
        return $filename
    }

    $Tasks = foreach ($key in $TemplateSettings.Keys) {
        if ($TemplateSettings[$key] -eq $true) {
            $key
        }
    }
    if ($TemplateSettings.templateRepo) {
        Write-Information 'Grabbing data from community repo'
        try {
            $Files = (Get-GitHubFileTree -FullName $TemplateSettings.templateRepo.value -Branch $TemplateSettings.templateRepoBranch.value).tree | Where-Object { $_.path -match '.json$' -and $_.path -notmatch 'NativeImport' } | Select-Object *, @{n = 'html_url'; e = { "https://github.com/$($SplatParams.FullName)/tree/$($SplatParams.Branch)/$($_.path)" } }, @{n = 'name'; e = { ($_.path -split '/')[ -1 ] -replace '\.json$', '' } }
            #if there is a migration table file, file the file. Store the file contents in $migrationtable
            $MigrationTable = $Files | Where-Object { $_.name -eq 'MigrationTable' } | Select-Object -Last 1
            if ($MigrationTable) {
                $MigrationTable = (Get-GitHubFileContents -FullName $TemplateSettings.templateRepo.value -Branch $TemplateSettings.templateRepoBranch.value -Path $MigrationTable.path).content | ConvertFrom-Json
            }
            foreach ($File in $Files) {
                if ($File.name -eq 'MigrationTable' -or $file.name -eq 'ALLOWED COUNTRIES') { continue }
                $ExistingTemplate = $ExistingTemplates | Where-Object { (![string]::IsNullOrEmpty($_.displayName) -and (Get-SanitizedFilename -filename $_.displayName) -eq $File.name) -or (![string]::IsNullOrEmpty($_.templateName) -and (Get-SanitizedFilename -filename $_.templateName) -eq $File.name ) -and ![string]::IsNullOrEmpty($_.SHA) } | Select-Object -First 1

                $UpdateNeeded = $false
                if ($ExistingTemplate -and $ExistingTemplate.SHA -ne $File.sha) {
                    $Name = $ExistingTemplate.displayName ?? $ExistingTemplate.templateName
                    Write-Information "Existing template $($Name) found, but SHA is different. Updating template."
                    $UpdateNeeded = $true
                    "Template $($Name) needs to be updated as the SHA is different"
                } else {
                    Write-Information "Existing template $($File.name) found, but SHA is the same. No update needed."
                    "Template $($File.name) found, but SHA is the same. No update needed."
                }

                if (!$ExistingTemplate -or $UpdateNeeded) {
                    $Template = (Get-GitHubFileContents -FullName $TemplateSettings.templateRepo.value -Branch $TemplateSettings.templateRepoBranch.value -Path $File.path).content | ConvertFrom-Json
                    Import-CommunityTemplate -Template $Template -SHA $File.sha -MigrationTable $MigrationTable
                    if ($UpdateNeeded) {
                        Write-Information "Template $($File.name) needs to be updated as the SHA is different"
                        "Template $($File.name) updated"
                    } else {
                        Write-Information "Template $($File.name) needs to be created"
                        "Template $($File.name) created"
                    }
                }
            }
        } catch {
            $Message = "Failed to get data from community repo $($TemplateSettings.templateRepo.value). Error: $($_.Exception.Message)"
            Write-LogMessage -API 'Community Repo' -tenant $TenantFilter -message $Message -sev Error
            return "Failed to get data from community repo $($TemplateSettings.templateRepo.value). Error: $($_.Exception.Message)"
        }
    } else {
        foreach ($Task in $Tasks) {
            Write-Information "Working on task $Task"
            switch ($Task) {
                'ca' {
                    Write-Information "Template Conditional Access Policies for $TenantFilter"
                    $Policies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/policies?$top=999' -tenantid $TenantFilter
                    Write-Information 'Creating templates for found Conditional Access Policies'
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
                    Write-Information "Backup Intune Configuration Policies for $TenantFilter"
                    $GraphURLS = @("https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$select=id,displayName,lastModifiedDateTime,roleScopeTagIds,microsoft.graph.unsupportedDeviceConfiguration/originalEntityTypeName&`$expand=assignments&top=1000"
                        'https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles'
                        "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?`$expand=assignments&top=999"
                        "https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations?`$expand=assignments&`$filter=microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig%20eq%20true"
                        'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
                        'https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles'
                        'https://graph.microsoft.com/beta/deviceManagement/windowsQualityUpdatePolicies'
                        'https://graph.microsoft.com/beta/deviceManagement/windowsQualityUpdateProfiles'
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
                            Write-Information "Failed to backup $url"
                        }
                    }
                }
                'intunecompliance' {
                    Write-Information "Backup Intune Compliance Policies for $TenantFilter"
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
                    Write-Information "Backup Intune Protection Policies for $TenantFilter"
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
    }
    return $BackupData
}

