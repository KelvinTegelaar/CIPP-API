function Invoke-ExecSAMAppPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    switch ($Request.Query.Action) {
        'Update' {
            try {
                $Permissions = $Request.Body.Permissions
                $Entity = @{
                    'PartitionKey' = 'CIPP-SAM'
                    'RowKey'       = 'CIPP-SAM'
                    'Permissions'  = [string]($Permissions.Permissions | ConvertTo-Json -Depth 10 -Compress)
                }
                $Table = Get-CIPPTable -TableName 'AppPermissions'
                $null = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
                $Body = @{
                    'Results' = 'Permissions Updated'
                }
            } catch {
                $Body = @{
                    'Results' = $_.Exception.Message
                }
            }
        }
        default {
            $Body = Get-CippSamPermissions
        }
    }


    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -Depth 10 -InputObject $Body
        })

}
