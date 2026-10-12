function Invoke-ExecValidateIntuneTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.Read
    .SYNOPSIS
        Check an Intune template for problems that would stop it deploying.
    .DESCRIPTION
        Runs the checks the store and deploy paths run and reports every finding. Nothing is written or
        deployed. Validates a stored template by ID, or a payload supplied directly. Supplying a tenant
        adds checks for unresolved replacement variables and settings the tenant does not offer.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # GUID of a stored template to validate. Omit when supplying RAWJson directly.
    $ID = $Request.Body.ID ?? $Request.Query.ID
    # Policy payload to validate as-is, instead of reading a stored template.
    $RawJSON = $Request.Body.RAWJson
    # Template type, e.g. Catalog or deviceCompliancePolicies. Inferred from the payload if omitted.
    $TemplateType = $Request.Body.TemplateType
    # Template display name, used to resolve the name the policy would deploy under.
    $DisplayName = $Request.Body.displayName
    # Tenant to run the tenant-specific checks against. Omit for static validation only.
    $TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    if ($TenantFilter -eq 'AllTenants') { $TenantFilter = $null }

    if (-not $ID -and -not $RawJSON) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Supply either a template ID or a policy payload to validate.' } })
    }

    if ($TenantFilter) {
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants' -and -not (Get-Tenants -TenantFilter $TenantFilter)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Forbidden; Body = @{ Results = 'Access to this tenant is not allowed' } })
        }
    }

    try {
        if (-not $RawJSON) {
            $Table = Get-CippTable -tablename 'templates'
            $SafeID = ConvertTo-CIPPODataFilterValue -Value $ID -Type String
            $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'IntuneTemplate' and RowKey eq '$SafeID'" | Select-Object -First 1
            if (-not $Entity) {
                throw [System.Management.Automation.ItemNotFoundException]::new("No Intune template found with ID $ID.")
            }
            $TemplateData = Repair-CIPPIntuneTemplateNesting -Template ($Entity.JSON | ConvertFrom-Json -Depth 100) -Table $Table
            $RawJSON = $TemplateData.RAWJson
            $TemplateType = $TemplateType ?? $TemplateData.Type
            $DisplayName = $DisplayName ?? $TemplateData.Displayname
        }

        $Params = @{
            RawJSON              = $RawJSON
            TemplateType         = $TemplateType
            DisplayName          = $DisplayName
            IncludeCatalogChecks = $true
        }
        if ($TenantFilter) { $Params.TenantFilter = $TenantFilter }
        $Validation = Test-CIPPIntuneTemplate @Params

        $Summary = if (-not $Validation.IsValid) {
            "Template '$($Validation.DisplayName)' would not deploy: $($Validation.Errors.Count) problem(s) found."
        } elseif ($Validation.Warnings.Count -gt 0) {
            "Template '$($Validation.DisplayName)' would deploy as type $($Validation.Type), with $($Validation.Warnings.Count) warning(s)."
        } else {
            "Template '$($Validation.DisplayName)' is valid and would deploy as type $($Validation.Type)."
        }
        $Results = @(
            @{ resultText = $Summary; state = $Validation.IsValid ? 'success' : 'error' }
            foreach ($Finding in $Validation.Findings) {
                @{
                    resultText = $Finding.Path ? "$($Finding.Path): $($Finding.Message)" : $Finding.Message
                    state      = $Finding.Severity -eq 'Error' ? 'error' : 'warning'
                }
            }
        )
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Validation failed: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Results }
        })
}
