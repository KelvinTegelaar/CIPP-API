function Invoke-AddPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Tenants = $Request.Body.tenantFilter.value ? $Request.Body.tenantFilter.value : $Request.Body.tenantFilter
    if ('AllTenants' -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }

    $DisplayName = $Request.Body.displayName
    $description = $Request.Body.Description
    $AssignTo = if ($Request.Body.AssignTo -ne 'on') { $Request.Body.AssignTo }
    $ExcludeGroup = $Request.Body.excludeGroup
    # Sent by the deploy drawer when a single tenant is selected and groups were picked by id.
    # customGroup/excludeGroup still carry the display names for logging and as a fallback.
    $GroupIds = @($Request.Body.GroupIds | Where-Object { $_ })
    $ExcludeGroupIds = @($Request.Body.ExcludeGroupIds | Where-Object { $_ })
    $AssignmentFilterSelection = $Request.Body.AssignmentFilterName ?? $Request.Body.assignmentFilter
    $AssignmentFilterType = $Request.Body.AssignmentFilterType ?? $Request.Body.assignmentFilterType
    $AssignmentFilterName = switch ($AssignmentFilterSelection) {
        { $_ -is [string] } { $_; break }
        { $_ -and $_.PSObject.Properties['value'] } { $_.value; break }
        { $_ -and $_.PSObject.Properties['displayName'] } { $_.displayName; break }
        { $_ -and $_.PSObject.Properties['label'] } { $_.label; break }
        default { $null }
    }
    $Request.Body.customGroup ? ($AssignTo = $Request.Body.customGroup) : $null
    $RawJSON = $Request.Body.RAWJson

    $Failed = 0
    $Results = foreach ($Tenant in $Tenants) {
        $TenantJSON = $RawJSON
        $reusableSettings = $Request.Body.ReusableSettings ?? $Request.Body.reusableSettings
        if (-not $reusableSettings -or $reusableSettings.Count -eq 0) {
            try {
                $templatesTable = Get-CippTable -tablename 'templates'
                # The deploy drawer and wizard send the chosen row's GUID as TemplateList.value, not
                # as TemplateID. Template display names are not unique - re-imports create same-named
                # twins - so resolving by display name below can land on a different row than the one
                # the user picked. The selected RowKey must win whenever the request carries one.
                # String rather than Guid: built-in templates are stored with their filename as RowKey.
                $SelectedTemplateId = ConvertTo-CIPPODataFilterValue -Value ($Request.Body.TemplateID ?? $Request.Body.TemplateId ?? $Request.Body.TemplateGuid ?? $Request.Body.TemplateGUID ?? $Request.Body.TemplateList.value) -Type String
                $templateEntity = Get-CIPPAzDataTableEntity @templatesTable -Filter "PartitionKey eq 'IntuneTemplate' and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $SelectedTemplateId)'" | Select-Object -First 1
                if (-not $templateEntity -and $DisplayName) {
                    $templateEntity = Get-CIPPAzDataTableEntity @templatesTable -Filter "PartitionKey eq 'IntuneTemplate'" | Where-Object { ($_.JSON | ConvertFrom-Json -ErrorAction SilentlyContinue).Displayname -eq $DisplayName } | Select-Object -First 1
                }
                if ($templateEntity) {
                    $templateObj = $templateEntity.JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $templateObj = Repair-CIPPIntuneTemplateNesting -Template $templateObj -Table $templatesTable
                    if ($templateObj.ReusableSettings) { $reusableSettings = $templateObj.ReusableSettings }
                    if ($templateObj.RAWJson) { $TenantJSON = $templateObj.RAWJson }
                }
            } catch {}
        }

        if ($Request.Body.replacemap.$Tenant -and $TenantJSON) {
            foreach ($Placeholder in ([pscustomobject]$Request.Body.replacemap.$Tenant).PSObject.Properties) {
                $Encoded = ConvertTo-Json -InputObject ([string]$Placeholder.Value) -Compress
                $TenantJSON = $TenantJSON.Replace($Placeholder.Name, $Encoded.Substring(1, $Encoded.Length - 2))
            }
        }

        if (-not $reusableSettings -and $TenantJSON) {
            try {
                # Discover referenced reusable settings from the policy JSON when none were supplied
                $reusableResult = Get-CIPPReusableSettingsFromPolicy -PolicyJson $TenantJSON -Tenant $Tenant -Headers $Headers -APIName $APIName
                if ($reusableResult.ReusableSettings) { $reusableSettings = $reusableResult.ReusableSettings }
                if ($reusableResult.RawJSON) { $TenantJSON = $reusableResult.RawJSON }
            } catch {}
        }

        $reusableSettingsForSet = $reusableSettings
        if ($Request.Body.TemplateType -eq 'Catalog') {
            $syncResult = Sync-CIPPReusablePolicySettings -TemplateInfo ([pscustomobject]@{ RawJSON = $TenantJSON; ReusableSettings = $reusableSettings }) -Tenant $Tenant
            if ($syncResult.RawJSON) { $TenantJSON = $syncResult.RawJSON }
            $reusableSettingsForSet = $null # helper already created/updated reusable settings and rewrote JSON
        }

        try {
            # Per tenant, because the replacemap above rewrites the payload.
            $Validation = Test-CIPPIntuneTemplate -RawJSON $TenantJSON -TemplateType $Request.Body.TemplateType -DisplayName $DisplayName
            if (-not $Validation.IsValid) {
                throw "Not deployed to $Tenant : $($Validation.Errors -join ' ')"
            }

            Write-Host 'Calling Adding policy'
            $params = @{
                # Resolved type: a template stored before Type was recorded arrives with none.
                TemplateType     = $Validation.Type
                Description      = $description
                DisplayName      = $DisplayName
                RawJSON          = $TenantJSON
                ReusableSettings = $reusableSettingsForSet
                AssignTo         = $AssignTo
                ExcludeGroup     = $ExcludeGroup
                tenantFilter     = $Tenant
                Headers          = $Headers
                APIName          = $APIName
            }
            if ($GroupIds.Count -gt 0) { $params.GroupIds = $GroupIds }
            if ($ExcludeGroupIds.Count -gt 0) { $params.ExcludeGroupIds = $ExcludeGroupIds }

            if (-not [string]::IsNullOrWhiteSpace($AssignmentFilterName)) {
                $params.AssignmentFilterName = $AssignmentFilterName
                $params.AssignmentFilterType = [string]::IsNullOrWhiteSpace($AssignmentFilterType) ? 'include' : $AssignmentFilterType
            }

            Set-CIPPIntunePolicy @params
        } catch {
            $Failed++
            "$($_.Exception.Message)"
            continue
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = Get-CippBulkStatusCode -Total @($Tenants).Count -Failed $Failed
            Body       = @{'Results' = @($Results) }
        })
}
