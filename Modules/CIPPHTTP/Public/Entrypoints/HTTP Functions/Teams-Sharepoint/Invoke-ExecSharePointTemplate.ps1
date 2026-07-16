function Invoke-ExecSharePointTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Sharepoint.Admin.ReadWrite
    .DESCRIPTION
        Saves, retrieves, deletes and deploys SharePoint provisioning templates. A template holds
        one or more site templates, each with its own document libraries and permission grants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Table = Get-CIPPTable -TableName 'templates'
    $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json

    $Action = $Request.Query.Action ?? $Request.Body.Action
    $StatusCode = [HttpStatusCode]::OK

    switch ($Action) {
        'Save' {
            try {
                # Every site template must carry at least one root-level permission object.
                $MissingPerms = @($Request.Body.siteTemplates | Where-Object { @($_.permissions).Count -eq 0 })
                if ($MissingPerms.Count -gt 0) {
                    $Names = ($MissingPerms | ForEach-Object { $_.displayName ?? 'Unnamed site' }) -join ', '
                    $Body = @{ Results = "Cannot save template: the following site templates have no root-level permission objects: $Names" }
                    $StatusCode = [HttpStatusCode]::BadRequest
                    break
                }

                $GUID = $Request.Body.TemplateId ?? (New-Guid).GUID

                # Keep only the template payload; strip transport/metadata fields.
                $TemplateObject = $Request.Body | Select-Object -Property * -ExcludeProperty Action, TemplateId

                # Stamp audit metadata. CreatedBy/On only on first save, UpdatedBy/On on every save.
                if (-not $Request.Body.TemplateId) {
                    $TemplateObject | Add-Member -NotePropertyName 'CreatedBy' -NotePropertyValue ($User.userDetails ?? 'CIPP-API') -Force
                    $TemplateObject | Add-Member -NotePropertyName 'CreatedOn' -NotePropertyValue (Get-Date).ToString('o') -Force
                }
                $TemplateObject | Add-Member -NotePropertyName 'UpdatedBy' -NotePropertyValue ($User.userDetails ?? 'CIPP-API') -Force
                $TemplateObject | Add-Member -NotePropertyName 'UpdatedOn' -NotePropertyValue (Get-Date).ToString('o') -Force
                $TemplateObject | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID -Force

                $TemplateJson = $TemplateObject | ConvertTo-Json -Depth 10 -Compress

                $Table.Force = $true
                Add-CIPPAzDataTableEntity @Table -Entity @{
                    JSON         = [string]$TemplateJson
                    RowKey       = "$GUID"
                    PartitionKey = 'SharePointTemplate'
                }

                $Body = @(
                    [PSCustomObject]@{
                        'Results'  = 'Template Saved'
                        'Metadata' = @{
                            'TemplateName' = $Request.Body.templateName
                            'TemplateId'   = $GUID
                        }
                    }
                )

                Write-LogMessage -headers $Headers -API $APIName -message "SharePoint Template Saved: $($Request.Body.templateName)" -Sev 'Info'
            } catch {
                $Body = @{
                    'Results' = $_.Exception.Message
                }
                $StatusCode = [HttpStatusCode]::InternalServerError
                Write-LogMessage -headers $Headers -API $APIName -message "SharePoint Template Save failed: $($_.Exception.Message)" -Sev 'Error'
            }
        }
        'Delete' {
            try {
                $TemplateId = $Request.Body.TemplateId ?? $Request.Query.TemplateId
                $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'SharePointTemplate' and RowKey eq '$TemplateId'"

                if ($Template) {
                    $TemplateName = ($Template.JSON | ConvertFrom-Json).templateName
                    $null = Remove-AzDataTableEntity @Table -Entity $Template -Force
                    $Body = @{
                        'Results' = "Successfully deleted template '$TemplateName'"
                    }
                    Write-LogMessage -headers $Headers -API $APIName -message "SharePoint Template deleted: $TemplateName" -Sev 'Info'
                } else {
                    $Body = @{
                        'Results' = 'No template found with the provided ID'
                    }
                }
            } catch {
                $Body = @{
                    'Results' = "Failed to delete template: $($_.Exception.Message)"
                }
                $StatusCode = [HttpStatusCode]::InternalServerError
                Write-LogMessage -headers $Headers -API $APIName -message "SharePoint Template Delete failed: $($_.Exception.Message)" -Sev 'Error'
            }
        }
        'Get' {
            $Filter = "PartitionKey eq 'SharePointTemplate'"
            if ($Request.Query.TemplateId) {
                $TemplateId = $Request.Query.TemplateId
                $Filter = "PartitionKey eq 'SharePointTemplate' and RowKey eq '$TemplateId'"
            }

            $Templates = Get-CIPPAzDataTableEntity @Table -Filter $Filter

            $Body = $Templates | ForEach-Object {
                $TemplateData = $_.JSON | ConvertFrom-Json
                $OutputObject = $TemplateData | Select-Object -Property *
                $OutputObject | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $_.RowKey -Force
                $OutputObject | Add-Member -NotePropertyName 'Timestamp' -NotePropertyValue $_.Timestamp.DateTime.ToString('yyyy-MM-ddTHH:mm:ssZ') -Force
                return $OutputObject
            }
        }
        'Deploy' {
            try {
                $TemplateId = $Request.Body.TemplateId
                $SiteOwner = $Request.Body.SiteOwner
                $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'SharePointTemplate' and RowKey eq '$TemplateId'"
                if (-not $Template) { throw 'No template found with the provided ID' }
                $TemplateData = $Template.JSON | ConvertFrom-Json
                if (-not $SiteOwner) { throw 'A site/team owner is required to deploy this template.' }

                # Expand AllTenants when selected in the drawer.
                $Tenants = foreach ($Tenant in $Request.Body.selectedTenants) {
                    if ($Tenant.defaultDomainName -eq 'AllTenants') {
                        (Get-Tenants).defaultDomainName
                    } else {
                        $Tenant.defaultDomainName
                    }
                }
                $Tenants = @($Tenants | Sort-Object -Unique)

                # Site and Team provisioning is slow (Teams sites can take a minute each), so the
                # actual work runs per tenant on the durable queue instead of in this request.
                $Queue = New-CippQueueEntry -Name "SharePoint Template - $($TemplateData.templateName)" -TotalTasks $Tenants.Count
                $Batch = foreach ($TenantFilter in $Tenants) {
                    [pscustomobject]@{
                        FunctionName = 'ExecSharePointTemplateDeploy'
                        Tenant       = $TenantFilter
                        TemplateId   = $TemplateId
                        SiteOwner    = $SiteOwner
                        QueueId      = $Queue.RowKey
                    }
                }
                $InputObject = @{
                    OrchestratorName = 'SharePointTemplateOrchestrator'
                    Batch            = @($Batch)
                    SkipLog          = $true
                }
                $null = Start-CIPPOrchestrator -InputObject $InputObject

                $Body = @{ Results = "Deployment of template '$($TemplateData.templateName)' queued for $($Tenants.Count) tenant(s). See the logbook for progress." }
                Write-LogMessage -headers $Headers -API $APIName -message "Queued SharePoint template deployment '$($TemplateData.templateName)' for $($Tenants.Count) tenant(s)" -Sev 'Info'
            } catch {
                $Body = @{ Results = "Failed to queue template deployment: $($_.Exception.Message)" }
                $StatusCode = [HttpStatusCode]::BadRequest
            }
        }
        default {
            $Filter = "PartitionKey eq 'SharePointTemplate'"
            $Templates = Get-CIPPAzDataTableEntity @Table -Filter $Filter

            $Body = $Templates | ForEach-Object {
                $TemplateData = $_.JSON | ConvertFrom-Json
                $OutputObject = $TemplateData | Select-Object -Property *
                $OutputObject | Add-Member -NotePropertyName 'TemplateId' -NotePropertyValue $_.RowKey -Force
                $OutputObject | Add-Member -NotePropertyName 'Timestamp' -NotePropertyValue $_.Timestamp.DateTime.ToString('yyyy-MM-ddTHH:mm:ssZ') -Force
                return $OutputObject
            }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -Depth 10 -InputObject @($Body)
        })
}
