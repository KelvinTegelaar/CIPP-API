function Invoke-ExecSAMAppPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json

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
                Write-LogMessage -headers $Headers -API $APIName -message 'CIPP-SAM Permissions Updated' -Sev 'Info' -LogData $Permissions
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                $Body = @{
                    'Results' = $_.Exception.Message
                }
                $StatusCode = [HttpStatusCode]::InternalServerError
            }
        }
        default {
            $Body = Get-CippSamPermissions
            $StatusCode = [HttpStatusCode]::OK
        }
    }

    return @{
        StatusCode = $StatusCode
        Body       = ConvertTo-Json -Depth 10 -InputObject $Body
    }

}
