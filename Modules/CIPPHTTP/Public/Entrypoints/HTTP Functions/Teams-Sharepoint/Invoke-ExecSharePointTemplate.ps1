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

                # Frontend sends TemplateId only when editing (add.js). Create/copy omit it.
                $GUID = $Request.Body.TemplateId
                if ([string]::IsNullOrWhiteSpace([string]$GUID)) {
                    $GUID = (New-Guid).GUID
                    $Existing = $null
                } else {
                    $GUID = [string]$GUID
                    $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'SharePointTemplate' and RowKey eq '$GUID'"
                }

                # Never trust client-supplied audit fields.
                $TemplateObject = $Request.Body | Select-Object -Property * -ExcludeProperty Action, TemplateId, GUID, CreatedBy, CreatedOn, UpdatedBy, UpdatedOn

                if ($Existing) {
                    $ExistingData = $Existing.JSON | ConvertFrom-Json
                    $TemplateObject | Add-Member -NotePropertyName 'CreatedBy' -NotePropertyValue ($ExistingData.CreatedBy ?? $User.userDetails ?? 'CIPP-API') -Force
                    $TemplateObject | Add-Member -NotePropertyName 'CreatedOn' -NotePropertyValue ($ExistingData.CreatedOn ?? (Get-Date).ToString('o')) -Force
                } else {
                    $TemplateObject | Add-Member -NotePropertyName 'CreatedBy' -NotePropertyValue ($User.userDetails ?? 'CIPP-API') -Force
                    $TemplateObject | Add-Member -NotePropertyName 'CreatedOn' -NotePropertyValue (Get-Date).ToString('o') -Force
                }
                $TemplateObject | Add-Member -NotePropertyName 'UpdatedBy' -NotePropertyValue ($User.userDetails ?? 'CIPP-API') -Force
                $TemplateObject | Add-Member -NotePropertyName 'UpdatedOn' -NotePropertyValue (Get-Date).ToString('o') -Force
                $TemplateObject | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID -Force
                # Always stamp the engine version this API understands; clients cannot omit or override.
                $TemplateObject | Add-Member -NotePropertyName 'templateEngineVersion' -NotePropertyValue 1 -Force

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

                $TenantFilter = $Request.Body.tenantFilter
                if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
                    throw 'A tenant is required to deploy this template.'
                }

                # Pre-create a status row so the frontend can poll live progress from queue time.
                $JobId = New-CIPPAsyncDeployment -Names @($TenantFilter) -StepTitles @(@($TemplateData.siteTemplates) | ForEach-Object { $_.displayName }) -Source 'SharePointTemplate'

                # Site and Team provisioning is slow (Teams sites can take a minute each), so the
                # actual work runs on the durable queue instead of in this request.
                $Queue = New-CippQueueEntry -Name "SharePoint Template - $($TemplateData.templateName)" -TotalTasks 1
                $InputObject = @{
                    OrchestratorName = 'SharePointTemplateOrchestrator'
                    Batch            = @(
                        [pscustomobject]@{
                            FunctionName = 'ExecSharePointTemplateDeploy'
                            Tenant       = $TenantFilter
                            TemplateId   = $TemplateId
                            SiteOwner    = $SiteOwner
                            DeploymentId = $JobId
                            QueueId      = $Queue.RowKey
                        }
                    )
                    SkipLog          = $true
                }
                $null = Start-CIPPOrchestrator -InputObject $InputObject

                $Body = @{
                    Results      = "Deployment of template '$($TemplateData.templateName)' queued for $TenantFilter."
                    DeploymentId = $JobId
                }
                Write-LogMessage -headers $Headers -API $APIName -message "Queued SharePoint template deployment '$($TemplateData.templateName)' for $TenantFilter" -Sev 'Info'
            } catch {
                $Body = @{ Results = "Failed to queue template deployment: $($_.Exception.Message)" }
                $StatusCode = [HttpStatusCode]::BadRequest
            }
        }
        'DeployStatus' {
            try {
                $JobId = $Request.Query.DeploymentId ?? $Request.Body.DeploymentId
                if (-not $JobId) { throw 'DeploymentId is required' }
                $Body = @(Get-CIPPAsyncDeployment -JobId $JobId)
            } catch {
                $Body = @{ Results = "Failed to get deployment status: $($_.Exception.Message)" }
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
