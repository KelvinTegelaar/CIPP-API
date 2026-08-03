function Invoke-ExecIntegrationTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Username = $Request.Headers.'x-ms-client-principal-name'

    $Action = $Request.Body.action ?? $Request.Query.action
    $TemplateId = $Request.Body.id ?? $Request.Query.id

    try {
        $Table = Get-CIPPTable -TableName 'templates'

        switch ($Action) {
            'save' {
                # Validate required fields
                if (-not $Request.Body.name) {
                    throw 'Template name is required'
                }
                if (-not $Request.Body.permissions -or $Request.Body.permissions.Count -eq 0) {
                    throw 'At least one permission is required'
                }

                # Generate new ID if not provided (new template)
                if (-not $TemplateId) {
                    $TemplateId = [guid]::NewGuid().ToString()
                }

                # Check if trying to modify a built-in template
                $BuiltInTemplatesPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\..\..\..\lib\data\IntegrationTemplates.json'
                if (Test-Path $BuiltInTemplatesPath) {
                    $BuiltInTemplates = Get-Content -Path $BuiltInTemplatesPath -Raw | ConvertFrom-Json
                    $IsBuiltIn = $BuiltInTemplates | Where-Object { $_.id -eq $TemplateId }
                    if ($IsBuiltIn) {
                        throw 'Cannot modify built-in templates. Use duplicate action instead.'
                    }
                }

                # Build template object
                $Template = @{
                    name                 = $Request.Body.name
                    description          = $Request.Body.description ?? ''
                    appNamePattern       = $Request.Body.appNamePattern ?? ($Request.Body.name + ' - {TenantName}')
                    redirectUris         = $Request.Body.redirectUris ?? @()
                    permissions          = $Request.Body.permissions
                    generateSecret       = $Request.Body.generateSecret ?? $true
                    secretExpirationDays = $Request.Body.secretExpirationDays ?? 730
                    documentationUrl     = $Request.Body.documentationUrl ?? ''
                }

                $Entity = @{
                    JSON         = ConvertTo-Json -InputObject $Template -Depth 10 -Compress
                    RowKey       = $TemplateId
                    PartitionKey = 'IntegrationTemplate'
                }

                Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

                Write-LogMessage -headers $Headers -API $APIName -user $Username -message "Saved integration template: $($Request.Body.name)" -Sev 'Info'

                $Results = @{
                    Results    = "Successfully saved template: $($Request.Body.name)"
                    TemplateId = $TemplateId
                }
            }

            'delete' {
                if (-not $TemplateId) {
                    throw 'Template ID is required for delete action'
                }

                # Check if trying to delete a built-in template
                $BuiltInTemplatesPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\..\..\..\lib\data\IntegrationTemplates.json'
                if (Test-Path $BuiltInTemplatesPath) {
                    $BuiltInTemplates = Get-Content -Path $BuiltInTemplatesPath -Raw | ConvertFrom-Json
                    $IsBuiltIn = $BuiltInTemplates | Where-Object { $_.id -eq $TemplateId }
                    if ($IsBuiltIn) {
                        throw 'Cannot delete built-in templates'
                    }
                }

                # Find and delete the template
                $Filter = "PartitionKey eq 'IntegrationTemplate' and RowKey eq '$TemplateId'"
                $ExistingTemplate = Get-CIPPAzDataTableEntity @Table -Filter $Filter

                if (-not $ExistingTemplate) {
                    throw "Template not found: $TemplateId"
                }

                Remove-CIPPAzDataTableEntity @Table -Entity $ExistingTemplate

                Write-LogMessage -headers $Headers -API $APIName -user $Username -message "Deleted integration template: $TemplateId" -Sev 'Info'

                $Results = @{
                    Results = "Successfully deleted template"
                }
            }

            'duplicate' {
                if (-not $TemplateId) {
                    throw 'Template ID is required for duplicate action'
                }

                # Load source template (could be built-in or custom)
                $SourceTemplate = $null

                # Check built-in templates first
                $BuiltInTemplatesPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\..\..\..\lib\data\IntegrationTemplates.json'
                if (Test-Path $BuiltInTemplatesPath) {
                    $BuiltInTemplates = Get-Content -Path $BuiltInTemplatesPath -Raw | ConvertFrom-Json
                    $SourceTemplate = $BuiltInTemplates | Where-Object { $_.id -eq $TemplateId }
                }

                # Check custom templates if not found in built-in
                if (-not $SourceTemplate) {
                    $Filter = "PartitionKey eq 'IntegrationTemplate' and RowKey eq '$TemplateId'"
                    $CustomTemplate = Get-CIPPAzDataTableEntity @Table -Filter $Filter
                    if ($CustomTemplate -and $CustomTemplate.JSON) {
                        $SourceTemplate = $CustomTemplate.JSON | ConvertFrom-Json
                    }
                }

                if (-not $SourceTemplate) {
                    throw "Source template not found: $TemplateId"
                }

                # Create new template with a new ID and modified name
                $NewTemplateId = [guid]::NewGuid().ToString()
                $NewName = $Request.Body.name ?? "$($SourceTemplate.name) (Copy)"

                $NewTemplate = @{
                    name                 = $NewName
                    description          = $SourceTemplate.description ?? ''
                    appNamePattern       = $SourceTemplate.appNamePattern -replace [regex]::Escape($SourceTemplate.name), $NewName
                    redirectUris         = $SourceTemplate.redirectUris ?? @()
                    permissions          = $SourceTemplate.permissions
                    generateSecret       = $SourceTemplate.generateSecret ?? $true
                    secretExpirationDays = $SourceTemplate.secretExpirationDays ?? 730
                    documentationUrl     = $SourceTemplate.documentationUrl ?? ''
                }

                $Entity = @{
                    JSON         = ConvertTo-Json -InputObject $NewTemplate -Depth 10 -Compress
                    RowKey       = $NewTemplateId
                    PartitionKey = 'IntegrationTemplate'
                }

                Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

                Write-LogMessage -headers $Headers -API $APIName -user $Username -message "Duplicated integration template: $($SourceTemplate.name) as $NewName" -Sev 'Info'

                $Results = @{
                    Results    = "Successfully duplicated template as: $NewName"
                    TemplateId = $NewTemplateId
                }
            }

            default {
                throw "Invalid action: $Action. Valid actions are: save, delete, duplicate"
            }
        }

        $StatusCode = [HttpStatusCode]::OK

    } catch {
        Write-LogMessage -headers $Headers -API $APIName -user $Username -message "Integration template operation failed: $($_.Exception.Message)" -Sev 'Error'
        $Results = @{
            Results = "Operation failed: $($_.Exception.Message)"
        }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -Depth 10 -InputObject $Results
        })
}
