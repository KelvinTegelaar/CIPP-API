function Invoke-ExecSAMAppPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json

    switch ($Request.Query.Action) {
        'Update' {
            try {
                $Permissions = $Request.Body.Permissions
                $Entity = @{
                    'PartitionKey' = 'CIPP-SAM'
                    'RowKey'       = 'CIPP-SAM'
                    'Permissions'  = [string]($Permissions | ConvertTo-Json -Depth 10 -Compress)
                    'UpdatedBy'    = $User.UserDetails ?? 'CIPP-API'
                }
                $Table = Get-CIPPTable -TableName 'AppPermissions'
                $null = Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
                $Body = @{
                    'Results' = 'Permissions Updated'
                }
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API 'ExecSAMAppPermissions' -message 'CIPP-SAM Permissions Updated' -Sev 'Info' -LogData $Permissions
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
