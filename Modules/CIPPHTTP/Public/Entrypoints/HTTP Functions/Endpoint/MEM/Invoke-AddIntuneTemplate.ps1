function Invoke-AddIntuneTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $GUID = (New-Guid).GUID
    try {
        if ($Request.Body.RawJSON) {
            if (!$Request.Body.displayName) { throw 'You must enter a displayName' }
            $Validation = Test-CIPPIntuneTemplate -RawJSON $Request.Body.RawJSON -TemplateType $Request.Body.TemplateType -DisplayName $Request.Body.displayName -IncludeCatalogChecks
            if (-not $Validation.IsValid) {
                throw [System.ArgumentException]::new("The template was not saved because it would not deploy: $($Validation.Errors -join ' ')")
            }

            $reusableTemplateRefs = @()
            $object = [PSCustomObject]@{
                Displayname      = $Request.Body.displayName
                Description      = $Request.Body.description
                RAWJson          = $Request.Body.RawJSON
                Type             = $Request.Body.TemplateType
                GUID             = $GUID
                ReusableSettings = $reusableTemplateRefs
            } | ConvertTo-Json
            $Table = Get-CippTable -tablename 'templates'
            $Table.Force = $true
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON                  = "$object"
                ReusableSettingsCount = $reusableTemplateRefs.Count
                RowKey                = "$GUID"
                PartitionKey          = 'IntuneTemplate'
                GUID                  = "$GUID"
            }
            Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Created intune policy template named $($Request.Body.displayName) with GUID $GUID" -Sev 'Info'

            $Result = 'Successfully added template'
            $StatusCode = [HttpStatusCode]::OK
        } else {
            $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter

            # AnyTenant: template is built from a live read of this tenant; enforce scope
            $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
            if ($AllowedTenants -notcontains 'AllTenants' -and -not ($TenantFilter -and (Get-Tenants -TenantFilter $TenantFilter))) {
                throw 'Access to this tenant is not allowed'
            }

            $URLName = $Request.Body.URLName ?? $Request.Query.URLName
            $ID = $Request.Body.ID ?? $Request.Query.ID
            $ODataType = $Request.Body.ODataType ?? $Request.Query.ODataType
            $Template = New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName $URLName -ID $ID -ODataType $ODataType

            $reusableResult = Get-CIPPReusableSettingsFromPolicy -PolicyJson $Template.TemplateJson -Tenant $TenantFilter -Headers $Headers -APIName $APIName
            $reusableTemplateRefs = $reusableResult.ReusableSettings
            # Intune templates store payload in RAWJson; only the content is rewritten to use reusable template GUID placeholders.
            $templateJson = if ($reusableResult.RawJSON) { $reusableResult.RawJSON } else { $Template.TemplateJson }

            $Table = Get-CippTable -tablename 'templates'
            $Replaced = $null
            $Dropped = [System.Collections.Generic.HashSet[string]]::new()
            # Replace the template with this policy's name instead of adding another one.
            if ($Request.Body.ReplaceExisting -eq $true) {
                $SameName = @(foreach ($Row in (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'IntuneTemplate'")) {
                        $Data = $(try { $Row.JSON | ConvertFrom-Json -Depth 100 } catch { $null })
                        if ($Data.Displayname -eq $Template.DisplayName) { @{ Row = $Row; Data = $Data } }
                    })
                if ($SameName.Count -gt 1) {
                    throw [System.ArgumentException]::new("$($SameName.Count) templates are named '$($Template.DisplayName)'. Rename all but one of them, then capture the policy again.")
                }
                foreach ($Candidate in $SameName) { $Replaced = $Candidate }
                if ($Replaced) {
                    $GUID = $Replaced.Row.RowKey
                    # Keep the %variables% added to the stored template where the policy still has those settings.
                    if ($Request.Body.KeepVariables -eq $true -and $Replaced.Data.RAWJson) {
                        $Merged = Merge-CIPPTemplateVariable -Existing ($Replaced.Data.RAWJson | ConvertFrom-Json -Depth 100) -Captured ($templateJson | ConvertFrom-Json -Depth 100) -Dropped $Dropped
                        $templateJson = ConvertTo-Json -InputObject $Merged -Depth 100 -Compress
                    }
                }
            }

            $Validation = Test-CIPPIntuneTemplate -RawJSON $templateJson -TemplateType $Template.Type -DisplayName $Template.DisplayName
            if (-not $Validation.IsValid) {
                throw [System.ArgumentException]::new("The captured policy did not produce a deployable template: $($Validation.Errors -join ' ')")
            }

            $object = [PSCustomObject]@{
                Displayname      = $Template.DisplayName
                Description      = $Template.Description
                RAWJson          = $templateJson
                Type             = $Template.Type
                GUID             = $GUID
                ReusableSettings = $reusableTemplateRefs
            } | ConvertTo-Json -Compress
            $Entity = @{
                JSON         = "$object"
                RowKey       = "$GUID"
                PartitionKey = 'IntuneTemplate'
            }
            if ($Replaced.Row.Package) { $Entity.Package = $Replaced.Row.Package }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
            Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "$(if ($Replaced) { 'Updated' } else { 'Created' }) intune policy template $($Template.DisplayName) with GUID $GUID using an original policy from a tenant" -Sev 'Info'

            $Result = if ($Replaced) { "Updated template '$($Template.DisplayName)'" } else { 'Successfully added template' }
            if ($Dropped.Count -gt 0) {
                $Result = @(
                    [pscustomobject]@{ state = 'success'; resultText = $Result }
                    [pscustomobject]@{ state = 'warning'; resultText = "These variables were on settings the policy no longer has, so they were not kept: $(@($Dropped) -join ', ')" }
                )
            }
            $StatusCode = [HttpStatusCode]::OK
        }
    } catch {
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Intune Template Deployment failed: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Result -Sev 'Error' -LogData $ErrorMessage
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result; GUID = $StatusCode -eq [HttpStatusCode]::OK ? $GUID : $null }
        })
}
