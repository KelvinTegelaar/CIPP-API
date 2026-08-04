function Invoke-ExecCippReplacemap {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Config.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'CippReplacemap'
    $Action = $Request.Query.Action ?? $Request.Body.Action
    $TenantId = $Request.Query.tenantId ?? $Request.Body.tenantId

    # Usage answers "where else does this variable name exist", which is a question about every
    # partition at once rather than about one tenant - so it is handled before the tenant is
    # resolved, and needs no tenantId.
    if ($Action -eq 'Usage') {
        $AllRows = Get-CIPPAzDataTableEntity @Table

        $TenantLookup = @{}
        foreach ($KnownTenant in (Get-Tenants -IncludeAll)) {
            if ($KnownTenant.customerId) { $TenantLookup[$KnownTenant.customerId] = $KnownTenant }
        }

        # The table stores one row per tenant, but a variable name is the unit an operator thinks in
        # - the same %wallpaperpath% deployed to many tenants - so group by name.
        $ByName = @{}
        foreach ($Row in $AllRows) {
            if (-not $Row.RowKey) { continue }
            if (-not $ByName.ContainsKey($Row.RowKey)) {
                $ByName[$Row.RowKey] = [System.Collections.Generic.List[object]]::new()
            }

            $IsGlobal = $Row.PartitionKey -eq 'AllTenants'
            $KnownTenant = if ($IsGlobal) { $null } else { $TenantLookup[$Row.PartitionKey] }

            $ByName[$Row.RowKey].Add([pscustomobject]@{
                    Scope        = if ($IsGlobal) { 'Global' } else { 'Tenant' }
                    TenantId     = if ($IsGlobal) { 'AllTenants' } else { $Row.PartitionKey }
                    # Rows written before the customerId convention key on a domain name, and a
                    # tenant that has since been removed will not resolve at all. Fall back to the
                    # raw partition key so the row is still identifiable rather than blank.
                    TenantName   = if ($IsGlobal) {
                        'All Tenants'
                    } elseif ($KnownTenant.displayName) {
                        $KnownTenant.displayName
                    } else {
                        $Row.PartitionKey
                    }
                    Value        = $Row.Value
                    VariableType = if ([string]::IsNullOrWhiteSpace($Row.VariableType)) { 'string' } else { $Row.VariableType }
                    Description  = $Row.Description
                })
        }

        $Usage = foreach ($Name in ($ByName.Keys | Sort-Object)) {
            $Definitions = @($ByName[$Name] | Sort-Object -Property @{ Expression = { $_.Scope -ne 'Global' } }, TenantName)
            $Types = @($Definitions | ForEach-Object { $_.VariableType } | Sort-Object -Unique)
            $GlobalDefinition = $Definitions | Where-Object { $_.Scope -eq 'Global' } | Select-Object -First 1

            [pscustomobject]@{
                Name            = $Name
                Variable        = "%$Name%"
                # What a new definition of this name should default to. The global one wins because
                # it is the closest thing to a canonical definition; otherwise the most common type
                # across the tenants that already have it.
                SuggestedType   = if ($GlobalDefinition) {
                    $GlobalDefinition.VariableType
                } else {
                    ($Definitions | Group-Object VariableType | Sort-Object Count -Descending | Select-Object -First 1).Name
                }
                HasGlobal       = [bool]$GlobalDefinition
                TenantCount     = @($Definitions | Where-Object { $_.Scope -eq 'Tenant' }).Count
                # The same name typed differently in different tenants substitutes differently in
                # each, which is drift worth surfacing rather than silently reconciling.
                TypesConsistent = ($Types.Count -le 1)
                Types           = $Types
                Definitions     = $Definitions
            }
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = @($Usage) }
            })
    }

    if ($TenantId -eq 'AllTenants') {
        $customerId = $TenantId
    } else {
        # ensure we use a consistent id for the table storage
        $Tenant = Get-Tenants -TenantFilter $TenantId
        $customerId = $Tenant.customerId
    }

    if (!$customerId) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'customerId is required'
            })
        return
    }

    switch ($Action) {
        'List' {
            $Variables = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$customerId'" | ForEach-Object {
                $_ | Add-Member -NotePropertyName 'Scope' -NotePropertyValue $(if ($customerId -eq 'AllTenants') { 'Global' } else { 'Tenant' }) -PassThru
            }
            if (!$Variables) {
                $Variables = @()
            }
            $IncludeGlobal = $Request.Query.includeGlobal ?? $Request.Body.includeGlobal
            if ($IncludeGlobal -eq 'true' -and $customerId -ne 'AllTenants') {
                $GlobalVariables = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AllTenants'" | ForEach-Object {
                    $_ | Add-Member -NotePropertyName 'Scope' -NotePropertyValue 'Global' -PassThru
                }
                if ($GlobalVariables) {
                    # A tenant value that shadows a global one is not simply 'Tenant'. Removing it
                    # restores the global value rather than deleting the variable, so the row is
                    # marked for what it is - the shadowed global is then dropped from the list
                    # below, which would otherwise leave no trace that it is being overridden.
                    $GlobalVarNames = @($GlobalVariables | ForEach-Object { $_.RowKey })
                    foreach ($Variable in $Variables) {
                        if ($Variable.RowKey -in $GlobalVarNames) {
                            $Variable.Scope = 'Overridden'
                        }
                    }

                    $TenantVarNames = @($Variables | ForEach-Object { $_.RowKey })
                    $GlobalVariables = @($GlobalVariables | Where-Object { $_.RowKey -notin $TenantVarNames })
                    $Variables = @($Variables) + @($GlobalVariables)
                }
            }
            $Body = @{ Results = @($Variables) }
        }
        'AddEdit' {
            $VariableName = $Request.Body.RowKey
            $VariableValue = $Request.Body.Value
            $VariableDescription = $Request.Body.Description

            # The type decides how the variable is written into a template. String is substituted as
            # text, exactly the way every variable always has been; integer, boolean and json are
            # written as JSON literals, so a numeric setting receives 300 rather than "300".
            #
            # Optional on purpose. Variables saved before this existed, and any caller that does not
            # send it, default to string and keep their original behaviour.
            #
            # The autocomplete that sets this posts {label, value}; a direct API call posts a plain
            # string. Accept either.
            $VariableType = $Request.Body.VariableType.value ?? $Request.Body.VariableType
            if ([string]::IsNullOrWhiteSpace($VariableType)) { $VariableType = 'string' }

            if ($VariableType -notin @('string', 'integer', 'boolean', 'json')) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ Results = "'$VariableType' is not a valid variable type. Use string, integer, boolean, or json." }
                    })
            }

            # Rejected here rather than at deployment: a mistyped value would otherwise silently fall
            # back to being substituted as a string, in a template that may not be deployed for days.
            $TrimmedValue = ([string]$VariableValue).Trim()
            switch ($VariableType) {
                'integer' {
                    $Parsed = [long]0
                    if (-not [long]::TryParse($TrimmedValue, [ref]$Parsed)) {
                        return ([HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body       = @{ Results = "Variable '$VariableName' is typed as integer, but '$VariableValue' is not a whole number." }
                            })
                    }
                }
                'boolean' {
                    if ($TrimmedValue -notin @('true', 'false', '1', '0', 'yes', 'no')) {
                        return ([HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body       = @{ Results = "Variable '$VariableName' is typed as boolean, but '$VariableValue' is not true or false." }
                            })
                    }
                }
                'json' {
                    try {
                        $null = ConvertFrom-Json -InputObject $TrimmedValue -Depth 100 -ErrorAction Stop
                    } catch {
                        return ([HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body       = @{ Results = "Variable '$VariableName' is typed as json, but its value is not valid JSON: $($_.Exception.Message)" }
                            })
                    }
                }
            }

            $VariableEntity = @{
                PartitionKey = $customerId
                RowKey       = $VariableName
                Value        = $VariableValue
                Description  = $VariableDescription
                VariableType = $VariableType
            }

            Add-CIPPAzDataTableEntity @Table -Entity $VariableEntity -Force
            $Body = @{ Results = "Variable '$VariableName' saved successfully" }
        }
        'Delete' {
            $VariableName = $Request.Body.RowKey

            $VariableEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$customerId' and RowKey eq '$VariableName'"
            if ($VariableEntity) {
                Remove-CIPPAzDataTableEntity @Table -Entity $VariableEntity -Force
                $Body = @{ Results = "Variable '$VariableName' deleted successfully" }
            } else {
                $Body = @{ Results = "Variable '$VariableName' not found" }
            }
        }
        default {
            $Body = @{ Results = 'Invalid action' }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
