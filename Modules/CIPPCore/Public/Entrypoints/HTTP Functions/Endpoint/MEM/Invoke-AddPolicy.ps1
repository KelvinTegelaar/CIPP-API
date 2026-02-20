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

    $Results = foreach ($Tenant in $Tenants) {
        if ($Request.Body.replacemap.$Tenant) {
            ([pscustomobject]$Request.Body.replacemap.$Tenant).PSObject.Properties | ForEach-Object { $RawJSON = $RawJSON -replace $_.name, $_.value }
        }

        $reusableSettings = $Request.Body.ReusableSettings ?? $Request.Body.reusableSettings
        if (-not $reusableSettings -or $reusableSettings.Count -eq 0) {
            try {
                $templatesTable = Get-CippTable -tablename 'templates'
                $templateEntity = Get-CIPPAzDataTableEntity @templatesTable -Filter "PartitionKey eq 'IntuneTemplate' and RowKey eq '$($Request.Body.TemplateID ?? $Request.Body.TemplateId ?? $Request.Body.TemplateGuid ?? $Request.Body.TemplateGUID)'" | Select-Object -First 1
                if (-not $templateEntity -and $DisplayName) {
                    $templateEntity = Get-CIPPAzDataTableEntity @templatesTable -Filter "PartitionKey eq 'IntuneTemplate'" | Where-Object { ($_.JSON | ConvertFrom-Json -ErrorAction SilentlyContinue).Displayname -eq $DisplayName } | Select-Object -First 1
                }
                if ($templateEntity) {
                    $templateObj = $templateEntity.JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($templateObj.ReusableSettings) { $reusableSettings = $templateObj.ReusableSettings }
                    if ($templateObj.RAWJson) { $RawJSON = $templateObj.RAWJson }
                }
            } catch {}
        }

        if (-not $reusableSettings -and $RawJSON) {
            try {
                # Discover referenced reusable settings from the policy JSON when none were supplied
                $reusableResult = Get-CIPPReusableSettingsFromPolicy -PolicyJson $RawJSON -Tenant $Tenant -Headers $Headers -APIName $APIName
                if ($reusableResult.ReusableSettings) { $reusableSettings = $reusableResult.ReusableSettings }
            } catch {}
        }

        $reusableSettingsForSet = $reusableSettings
        if ($Request.Body.TemplateType -eq 'Catalog') {
            $syncResult = Sync-CIPPReusablePolicySettings -TemplateInfo ([pscustomobject]@{ RawJSON = $RawJSON; ReusableSettings = $reusableSettings }) -Tenant $Tenant
            if ($syncResult.RawJSON) { $RawJSON = $syncResult.RawJSON }
            $reusableSettingsForSet = $null # helper already created/updated reusable settings and rewrote JSON
        }

        try {
            Write-Host 'Calling Adding policy'
            $params = @{
                TemplateType     = $Request.Body.TemplateType
                Description      = $description
                DisplayName      = $DisplayName
                RawJSON          = $RawJSON
                ReusableSettings = $reusableSettingsForSet
                AssignTo         = $AssignTo
                ExcludeGroup     = $ExcludeGroup
                tenantFilter     = $Tenant
                Headers          = $Headers
                APIName          = $APIName
            }

            if (-not [string]::IsNullOrWhiteSpace($AssignmentFilterName)) {
                $params.AssignmentFilterName = $AssignmentFilterName
                $params.AssignmentFilterType = [string]::IsNullOrWhiteSpace($AssignmentFilterType) ? 'include' : $AssignmentFilterType
            }

            Set-CIPPIntunePolicy @params
        } catch {
            "$($_.Exception.Message)"
            continue
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{'Results' = @($Results) }
        })
}
