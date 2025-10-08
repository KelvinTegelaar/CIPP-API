function Invoke-ExecAppPermissionTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.ApplicationTemplates.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers


    $Table = Get-CIPPTable -TableName 'AppPermissions'

    $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json

    $Action = $Request.Query.Action ?? $Request.Body.Action

    switch ($Action) {
        'Save' {
            try {
                $RowKey = $Request.Body.TemplateId ?? [guid]::NewGuid().ToString()
                $Permissions = $Request.Body.Permissions
                $Entity = @{
                    'PartitionKey' = 'Templates'
                    'RowKey'       = [string]$RowKey
                    'TemplateName' = [string]$Request.Body.TemplateName
                    'Permissions'  = [string]($Permissions | ConvertTo-Json -Depth 10 -Compress)
                    'UpdatedBy'    = $User.UserDetails ?? 'CIPP-API'
                }
                $null = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
                $Body = @{
                    'Results'  = 'Template Saved'
                    'Metadata' = @{
                        'TemplateName' = $Entity.TemplateName
                        'TemplateId'   = $RowKey
                    }
                }
                Write-LogMessage -headers $Headers -API 'ExecAppPermissionTemplate' -message "Permissions Saved for template: $($Request.Body.TemplateName)" -Sev 'Info' -LogData $Permissions
            } catch {
                Write-Information "Failed to save template: $($_.Exception.Message) - $($_.InvocationInfo.PositionMessage)"
                $Body = @{
                    'Results' = $_.Exception.Message
                }
            }
        }
        'Delete' {
            try {
                $TemplateId = $Request.Body.TemplateId
                $Template = (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Templates' and RowKey eq '$TemplateId'")
                $TemplateName = $Template.TemplateName

                if ($TemplateId) {
                    $null = Remove-AzDataTableEntity @Table -Entity $Template -Force
                    $Body = @{
                        'Results' = "Successfully deleted template '$TemplateName'"
                    }
                    Write-LogMessage -headers $Headers -API 'ExecAppPermissionTemplate' -message "Permission template deleted: $TemplateName" -Sev 'Info'
                } else {
                    $Body = @{
                        'Results' = 'No Template ID provided for deletion'
                    }
                }
            } catch {
                $Body = @{
                    'Results' = "Failed to delete template: $($_.Exception.Message)"
                }
            }
        }
        default {
            # Check if TemplateId is provided to filter results
            $filter = "PartitionKey eq 'Templates'"
            if ($Request.Query.TemplateId) {
                $templateId = $Request.Query.TemplateId
                $filter = "PartitionKey eq 'Templates' and RowKey eq '$templateId'"
                Write-LogMessage -headers $Headers -API 'ExecAppPermissionTemplate' -message "Retrieved specific template: $templateId" -Sev 'Info'
            }

            $Body = Get-CIPPAzDataTableEntity @Table -Filter $filter | ForEach-Object {
                [PSCustomObject]@{
                    TemplateId   = $_.RowKey
                    TemplateName = $_.TemplateName
                    Permissions  = $_.Permissions | ConvertFrom-Json
                    UpdatedBy    = $_.UpdatedBy
                    Timestamp    = $_.Timestamp.DateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
            }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -Depth 10 -InputObject @($Body)
        })

}
