function Invoke-ExecAppPermissionTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CIPPTable -TableName 'AppPermissions'

    $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json

    switch ($Request.Query.Action) {
        'Save' {
            try {
                $Permissions = $Request.Body.Permissions
                $Entity = @{
                    'PartitionKey' = 'Templates'
                    'RowKey'       = [string]($Request.Body.TemplateId ?? [guid]::NewGuid().ToString())
                    'TemplateName' = [string]$Request.Body.TemplateName
                    'Permissions'  = [string]($Permissions | ConvertTo-Json -Depth 10 -Compress)
                    'UpdatedBy'    = $User.UserDetails ?? 'CIPP-API'
                }
                $null = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
                $Body = @{
                    'Results'    = 'Template Saved'
                    'TemplateId' = $Entity.RowKey
                }
                Write-LogMessage -headers $Request.Headers -API 'ExecAppPermissionTemplate' -message "Permissions Saved for template: $($Request.Body.TemplateName)" -Sev 'Info' -LogData $Permissions
            } catch {
                $Body = @{
                    'Results' = $_.Exception.Message
                }
            }
        }
        default {
            $Body = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Templates'" | ForEach-Object {
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

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -Depth 10 -InputObject @($Body)
        })

}
