Function Invoke-ExecPasswordConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CIPPTable -TableName Settings
    $PasswordType = (Get-CIPPAzDataTableEntity @Table)


    $results = try {
        if ($Request.Query.List) {
            @{ passwordType = $PasswordType.passwordType }
        } else {
            $PasswordConfig = @{
                'passwordType'  = "$($Request.Body.passwordType)"
                'passwordCount' = '12'
                'PartitionKey'  = 'settings'
                'RowKey'        = 'settings'
            }

            Add-CIPPAzDataTableEntity @Table -Entity $PasswordConfig -Force | Out-Null
            'Successfully set the configuration'
        }
    } catch {
        "Failed to set configuration: $($_.Exception.message)"
    }


    $body = [pscustomobject]@{'Results' = $Results }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
