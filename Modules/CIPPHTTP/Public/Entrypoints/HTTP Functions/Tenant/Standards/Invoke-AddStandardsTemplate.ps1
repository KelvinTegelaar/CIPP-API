function Invoke-AddStandardsTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    if ($Request.Body.tenantFilter -eq 'tenantFilter') {
        throw 'Invalid Tenant Selection. A standard must be assigned to at least 1 tenant.'
    }

    # tenantFilter is a *list* (and may include AllTenants or tenant groups), so this endpoint is
    # AnyTenant and validates the whole list here: standards runs execute app-level without
    # re-checking custom-role access, so this is the boundary that stops a scoped caller assigning
    # standards to tenants outside their scope.
    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants') {
        $OutOfScope = foreach ($Item in @($Request.Body.tenantFilter)) {
            if ($Item.value -eq 'AllTenants') {
                # Assigning to every tenant requires an unrestricted (AllTenants) scope.
                'All Tenants'
                continue
            }
            if ($Item.type -eq 'Group') {
                foreach ($TargetId in @(Expand-CIPPTenantGroups -TenantFilter @($Item)).addedFields.customerId) {
                    if ($AllowedTenants -notcontains $TargetId) { $Item.label ?? $Item.value }
                }
                continue
            }
            # Single tenant: resolve to a customerId. An unresolved value is $null, which is never
            # in the allowed list, so -notcontains fails closed on its own.
            $TargetId = $Item.addedFields.customerId ?? (Get-Tenants -TenantFilter $Item.value).customerId
            if ($AllowedTenants -notcontains $TargetId) {
                $Item.label ?? $Item.value
            }
        }
        if (($OutOfScope | Measure-Object).Count -gt 0) {
            $Denied = $OutOfScope -join ', '
            Write-LogMessage -headers $Headers -API $APIName -message "Blocked standards template save; caller is not permitted for: $Denied" -Sev 'Warning'
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = "Access to one or more of the selected tenants is not allowed: $Denied"
                })
        }
    }

    $GUID = $Request.body.GUID ? $request.body.GUID : (New-Guid).GUID
    #updatedBy    = $request.headers.'x-ms-client-principal'
    #updatedAt    = (Get-Date).ToUniversalTime()
    $request.body | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID -Force
    $request.body | Add-Member -NotePropertyName 'createdAt' -NotePropertyValue ($Request.body.createdAt ? $Request.body.createdAt : (Get-Date).ToUniversalTime()) -Force
    $Request.body | Add-Member -NotePropertyName 'updatedBy' -NotePropertyValue ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails -Force
    $Request.body | Add-Member -NotePropertyName 'updatedAt' -NotePropertyValue (Get-Date).ToUniversalTime() -Force
    $JSON = (ConvertTo-Json -Compress -Depth 100 -InputObject ($Request.body))
    $Table = Get-CippTable -tablename 'templates'
    $Table.Force = $true
    Add-CIPPAzDataTableEntity @Table -Entity @{
        JSON         = "$JSON"
        RowKey       = "$GUID"
        PartitionKey = 'StandardsTemplateV2'
        GUID         = "$GUID"
    }

    $AddObject = @{
        PartitionKey = 'InstanceProperties'
        RowKey       = 'CIPPURL'
        Value        = [string]([System.Uri]$Headers.'x-ms-original-url').Host
    }
    $ConfigTable = Get-CIPPTable -tablename 'Config'
    Add-AzDataTableEntity @ConfigTable -Entity $AddObject -Force

    Write-LogMessage -headers $Request.Headers -API $APINAME -message "Standards Template $($Request.body.templateName) with GUID $GUID added/edited." -Sev 'Info'
    $body = [pscustomobject]@{'Results' = 'Successfully added template'; Metadata = @{id = $GUID } }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
