function New-CIPPTemplateRun {
    [CmdletBinding()]
    param (
        $TemplateSettings,
        $TenantFilter
    )
    $Table = Get-CippTable -tablename 'templates'

    # Templates created from a tenant are keyed by that tenant in their Source column and matched
    # on it to update-in-place. The tenant can be addressed by any of its names (default domain,
    # initial onmicrosoft domain, tenant id), and a second sync task created under a different name
    # used to see none of the existing templates and create a full duplicate set on every run.
    # Match on every name the tenant is known by and write the canonical one.
    $TenantInfo = Get-Tenants -IncludeErrors -TenantFilter $TenantFilter | Select-Object -First 1
    $SourceAliases = @(@($TenantFilter, $TenantInfo.defaultDomainName, $TenantInfo.initialDomainName, $TenantInfo.customerId) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $SourceName = if ($TenantInfo.defaultDomainName) { [string]$TenantInfo.defaultDomainName } else { [string]$TenantFilter }

    $ExistingTemplates = (Get-CIPPAzDataTableEntity @Table) | ForEach-Object {
        try {
            $data = $_.JSON | ConvertFrom-Json -ErrorAction SilentlyContinue -Depth 100
            $data | Add-Member -NotePropertyMembers ([ordered]@{
                    GUID         = $_.RowKey
                    PartitionKey = $_.PartitionKey
                }) -Force -ErrorAction Stop
            $data | Add-Member -NotePropertyMembers ([ordered]@{
                    SHA     = $_.SHA
                    Package = $_.Package
                    Source  = $_.Source
                }) -Force -ErrorAction SilentlyContinue
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
            $NamedLocations = $Files | Where-Object { $_.name -match 'ALLOWED COUNTRIES' }
            $LocationData = foreach ($Location in $NamedLocations) {
                (Get-GitHubFileContents -FullName $TemplateSettings.templateRepo.value -Branch $TemplateSettings.templateRepoBranch.value -Path $Location.path).content | ConvertFrom-Json
            }

            foreach ($File in $Files) {
                if ($File.name -eq 'MigrationTable' -or $file.name -match 'ALLOWED COUNTRIES') { continue }
                Write-Information "Processing template file $($File.name) - Sanitized as $(Get-SanitizedFilename -filename $File.name)"
                $ExistingTemplate = $ExistingTemplates | Where-Object { (![string]::IsNullOrEmpty($_.displayName) -and (Get-SanitizedFilename -filename $_.displayName) -eq (Get-SanitizedFilename -filename $File.name)) -or (![string]::IsNullOrEmpty($_.templateName) -and (Get-SanitizedFilename -filename $_.templateName) -eq (Get-SanitizedFilename -filename $File.name) ) -and ![string]::IsNullOrEmpty($_.SHA) } | Select-Object -First 1

                $UpdateNeeded = $false
                if ($ExistingTemplate -and $ExistingTemplate.SHA -ne $File.sha -and $ExistingTemplate.Source -eq $TemplateSettings.templateRepo.value) {
                    $Name = $ExistingTemplate.displayName ?? $ExistingTemplate.templateName
                    Write-Information "Existing template $($Name) found, but SHA is different. Updating template."
                    $UpdateNeeded = $true
                    "Template $($Name) needs to be updated as the SHA is different"
                } elseif ($ExistingTemplate -and $ExistingTemplate.SHA -eq $File.sha -and $ExistingTemplate.Source -eq $TemplateSettings.templateRepo.value) {
                    Write-Information "Existing template $($File.name) found, but SHA is the same. No update needed."
                    "Template $($File.name) found, but SHA is the same. No update needed."
                }

                if (!$ExistingTemplate -or $UpdateNeeded) {
                    $Template = (Get-GitHubFileContents -FullName $TemplateSettings.templateRepo.value -Branch $TemplateSettings.templateRepoBranch.value -Path $File.path).content | ConvertFrom-Json
                    $ImportResult = Import-CommunityTemplate -Template $Template -SHA $File.sha -MigrationTable $MigrationTable -LocationData $LocationData -Source $TemplateSettings.templateRepo.value
                    if ($ImportResult) {
                        Write-Information $ImportResult
                        $ImportResult
                    } elseif ($UpdateNeeded) {
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
            Write-Information $_.InvocationInfo.PositionMessage
            return "Failed to get data from community repo $($TemplateSettings.templateRepo.value). Error: $($_.Exception.Message)"
        }
    } else {
        # Tenant template library
        $Results = foreach ($Task in $Tasks) {
            switch ($Task) {
                'ca' {
                    Write-Information "Template Conditional Access Policies for $TenantFilter"
                    # Preload users/groups for CA templates
                    Write-Information "Preloading information for Conditional Access templates for $TenantFilter"
                    $Requests = @(
                        @{
                            id     = 'preloadedUsers'
                            url    = 'users?$top=999&$select=displayName,id'
                            method = 'GET'
                        }
                        @{
                            id     = 'preloadedGroups'
                            url    = 'groups?$top=999&$select=displayName,id'
                            method = 'GET'
                        }
                        @{
                            id     = 'conditionalAccessPolicies'
                            url    = 'conditionalAccess/policies?$top=999'
                            method = 'GET'
                        }
                    )
                    $BulkResults = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -asapp $true
                    $preloadedUsers = ($BulkResults | Where-Object { $_.id -eq 'preloadedUsers' }).body.value
                    $preloadedGroups = ($BulkResults | Where-Object { $_.id -eq 'preloadedGroups' }).body.value
                    $policies = ($BulkResults | Where-Object { $_.id -eq 'conditionalAccessPolicies' }).body.value

                    Write-Information 'Creating templates for found Conditional Access Policies'
                    foreach ($policy in $policies) {
                        try {
                            $Hash = Get-StringHash -String ($policy | ConvertTo-Json -Depth 100 -Compress)
                            $ExistingPolicy = $ExistingTemplates | Where-Object { $_.PartitionKey -eq 'CATemplate' -and $_.displayName -eq $policy.displayName -and $_.Source -in $SourceAliases } | Select-Object -First 1
                            if ($ExistingPolicy -and $ExistingPolicy.SHA -eq $Hash) {
                                "CA Policy $($policy.displayName) found, SHA matches, skipping template creation"
                                continue
                            }
                            $Template = New-CIPPCATemplate -TenantFilter $TenantFilter -JSON $policy -preloadedUsers $preloadedUsers -preloadedGroups $preloadedGroups
                            #check existing templates, if the displayName is the same, overwrite it.

                            if ($ExistingPolicy -and $ExistingPolicy.PartitionKey -eq 'CATemplate') {
                                "CA Policy $($policy.displayName) found, updating template"
                                # Full replace: carry Package across like the Intune branches do.
                                Add-CIPPAzDataTableEntity @Table -Entity @{
                                    JSON         = "$Template"
                                    RowKey       = $ExistingPolicy.GUID
                                    PartitionKey = 'CATemplate'
                                    Package      = $ExistingPolicy.Package
                                    GUID         = $ExistingPolicy.GUID
                                    SHA          = $Hash
                                    Source       = $ExistingPolicy.Source
                                } -Force
                            } else {
                                "CA Policy $($policy.displayName) not found in existing templates, creating new template"
                                $GUID = (New-Guid).GUID
                                Add-CIPPAzDataTableEntity @Table -Entity @{
                                    JSON         = "$Template"
                                    RowKey       = "$GUID"
                                    PartitionKey = 'CATemplate'
                                    GUID         = "$GUID"
                                    SHA          = $Hash
                                    Source       = $SourceName
                                }
                            }

                        } catch {
                            "Failed to create a template of the Conditional Access Policy with ID: $($policy.id). Error: $($_.Exception.Message)"
                        }
                    }
                }
                'intuneconfig' {
                    Write-Information "Backup Intune Configuration Policies for $TenantFilter"
                    $GraphURLS = @(
                        "deviceManagement/deviceConfigurations?`$select=id,displayName,lastModifiedDateTime,roleScopeTagIds,microsoft.graph.unsupportedDeviceConfiguration/originalEntityTypeName&`$expand=assignments&top=1000"
                        'deviceManagement/windowsDriverUpdateProfiles'
                        "deviceManagement/groupPolicyConfigurations?`$expand=assignments&top=999"
                        "deviceAppManagement/mobileAppConfigurations?`$expand=assignments&`$filter=microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig%20eq%20true"
                        'deviceManagement/configurationPolicies'
                        'deviceManagement/windowsFeatureUpdateProfiles'
                        'deviceManagement/windowsQualityUpdatePolicies'
                        'deviceManagement/windowsQualityUpdateProfiles'
                        'deviceManagement/hardwareConfigurations'
                    )

                    $Requests = [System.Collections.Generic.List[PSCustomObject]]::new()
                    foreach ($url in $GraphURLS) {
                        $URLName = (($url).split('?') | Select-Object -First 1) -replace 'deviceManagement/', '' -replace 'deviceAppManagement/', ''
                        $Requests.Add([PSCustomObject]@{
                                id     = $URLName
                                url    = $url
                                method = 'GET'
                            })
                    }
                    $BulkResults = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter
                    foreach ($Result in $BulkResults) {
                        Write-Information "Processing Intune Configuration Policies for $($Result.id) - Status Code: $($Result.status)"
                        if ($Result.status -eq 200) {
                            $URLName = $Result.id
                            $Policies = $Result.body.value
                            Write-Information "Found $($Policies.Count) policies for $($Result.id)"
                            foreach ($Policy in $Policies) {
                                try {
                                    $Hash = Get-StringHash -String ($Policy | ConvertTo-Json -Depth 100 -Compress)
                                    $DisplayName = $Policy.displayName ?? $Policy.name

                                    $ExistingPolicy = $ExistingTemplates | Where-Object { $_.PartitionKey -eq 'IntuneTemplate' -and $_.displayName -eq $DisplayName -and $_.Source -in $SourceAliases } | Select-Object -First 1

                                    Write-Information "Processing Intune Configuration Policy $($DisplayName) - $($ExistingPolicy ? 'Existing template found' : 'No existing template found')"

                                    if ($ExistingPolicy -and $ExistingPolicy.SHA -eq $Hash) {
                                        "Intune Configuration Policy $($DisplayName) found, SHA matches, skipping template creation"
                                        continue
                                    }

                                    $Template = New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName $URLName -ID $Policy.id
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
                                            Package      = $ExistingPolicy.Package
                                            GUID         = $ExistingPolicy.GUID
                                            SHA          = $Hash
                                            Source       = $ExistingPolicy.Source
                                        } -Force
                                    } else {
                                        "Intune Configuration Policy $($Template.DisplayName) not found in existing templates, creating new template"
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
                                            GUID         = "$GUID"
                                            SHA          = $Hash
                                            Source       = $SourceName
                                        } -Force
                                    }
                                } catch {
                                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                                    "Failed to create a template of the Intune Configuration Policy with ID: $($Policy.id). Error: $ErrorMessage"
                                }
                            }
                        } else {
                            Write-Information "Failed to get $($Result.id) policies - Status Code: $($Result.status) - Message: $($Result.body.error.message)"
                        }
                    }
                }
                'intunecompliance' {
                    Write-Information "Create Intune Compliance Policy Templates for $TenantFilter"
                    $Policies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?$top=999' -tenantid $TenantFilter
                    foreach ($Policy in $Policies) {
                        try {
                            $Hash = Get-StringHash -String (ConvertTo-Json -Depth 100 -Compress -InputObject $Policy)
                            $ExistingPolicy = $ExistingTemplates | Where-Object { $_.PartitionKey -eq 'IntuneTemplate' -and $Policy.displayName -eq $_.DisplayName -and $_.Source -in $SourceAliases } | Select-Object -First 1
                            if ($ExistingPolicy -and $ExistingPolicy.SHA -eq $Hash) {
                                "Intune Compliance Policy $($Policy.displayName) found, SHA matches, skipping template creation"
                                continue
                            }

                            $Template = New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName 'deviceCompliancePolicies' -ID $Policy.id
                            if ($ExistingPolicy -and $ExistingPolicy.PartitionKey -eq 'IntuneTemplate') {
                                "Intune Compliance Policy $($Template.DisplayName) found, updating template"
                                $object = [PSCustomObject]@{
                                    Displayname = $Template.DisplayName
                                    Description = $Template.Description
                                    RAWJson     = $Template.TemplateJson
                                    Type        = $Template.Type
                                    GUID        = $ExistingPolicy.GUID
                                } | ConvertTo-Json -Compress

                                Add-CIPPAzDataTableEntity @Table -Entity @{
                                    JSON         = "$object"
                                    RowKey       = $ExistingPolicy.GUID
                                    PartitionKey = 'IntuneTemplate'
                                    Package      = $ExistingPolicy.Package
                                    GUID         = $ExistingPolicy.GUID
                                    SHA          = $Hash
                                    Source       = $ExistingPolicy.Source
                                } -Force
                            } else {
                                "Intune Compliance Policy $($Template.DisplayName) not found in existing templates, creating new template"
                                $GUID = (New-Guid).GUID
                                $object = [PSCustomObject]@{
                                    Displayname = $Template.DisplayName
                                    Description = $Template.Description
                                    RAWJson     = $Template.TemplateJson
                                    Type        = $Template.Type
                                    GUID        = $GUID
                                } | ConvertTo-Json -Compress

                                Add-CIPPAzDataTableEntity @Table -Entity @{
                                    JSON         = "$object"
                                    RowKey       = "$GUID"
                                    PartitionKey = 'IntuneTemplate'
                                    SHA          = $Hash
                                    GUID         = "$GUID"
                                    Source       = $SourceName
                                } -Force
                            }
                        } catch {
                            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                            "Failed to create a template of the Intune Compliance Policy with ID: $($Policy.id). Error: $ErrorMessage"
                        }
                    }
                }

                'intuneprotection' {
                    Write-Information "Create Intune Protection Policy Templates for $TenantFilter"
                    $Policies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/managedAppPolicies?$top=999' -tenantid $TenantFilter
                    foreach ($Policy in $Policies) {
                        try {
                            $Hash = Get-StringHash -String (ConvertTo-Json -Depth 100 -Compress -InputObject $Policy)
                            $ExistingPolicy = $ExistingTemplates | Where-Object { $_.PartitionKey -eq 'IntuneTemplate' -and $Policy.displayName -eq $_.DisplayName -and $_.Source -in $SourceAliases } | Select-Object -First 1
                            if ($ExistingPolicy -and $ExistingPolicy.SHA -eq $Hash) {
                                "Intune Protection Policy $($Policy.displayName) found, SHA matches, skipping template creation"
                                continue
                            }

                            $Template = New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName 'managedAppPolicies' -ID $Policy.id -ODataType $Policy.'@odata.type'
                            if ($ExistingPolicy -and $ExistingPolicy.PartitionKey -eq 'IntuneTemplate') {
                                "Intune Protection Policy $($Template.DisplayName) found, updating template"
                                $object = [PSCustomObject]@{
                                    Displayname = $Template.DisplayName
                                    Description = $Template.Description
                                    RAWJson     = $Template.TemplateJson
                                    Type        = $Template.Type
                                    GUID        = $ExistingPolicy.GUID
                                } | ConvertTo-Json -Compress

                                Add-CIPPAzDataTableEntity @Table -Entity @{
                                    JSON         = "$object"
                                    RowKey       = $ExistingPolicy.GUID
                                    PartitionKey = 'IntuneTemplate'
                                    Package      = $ExistingPolicy.Package
                                    SHA          = $Hash
                                    GUID         = $ExistingPolicy.GUID
                                    Source       = $ExistingPolicy.Source
                                } -Force
                            } else {
                                "Intune Protection Policy $($Template.DisplayName) not found in existing templates, creating new template"
                                $GUID = (New-Guid).GUID
                                $object = [PSCustomObject]@{
                                    Displayname = $Template.DisplayName
                                    Description = $Template.Description
                                    RAWJson     = $Template.TemplateJson
                                    Type        = $Template.Type
                                    GUID        = $GUID
                                } | ConvertTo-Json -Compress

                                Add-CIPPAzDataTableEntity @Table -Entity @{
                                    JSON         = "$object"
                                    RowKey       = "$GUID"
                                    PartitionKey = 'IntuneTemplate'
                                    SHA          = $Hash
                                    GUID         = "$GUID"
                                    Source       = $SourceName
                                } -Force
                            }
                        } catch {
                            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                            "Failed to create a template of the Intune Protection Policy with ID: $($Policy.id). Error: $ErrorMessage"
                        }
                    }
                }
            }
        }
    }
    return $Results
}
