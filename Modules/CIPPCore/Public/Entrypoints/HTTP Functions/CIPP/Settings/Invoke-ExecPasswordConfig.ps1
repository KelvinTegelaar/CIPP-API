using namespace System.Net

function Invoke-ExecPasswordConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CIPPTable -TableName Settings
    $PasswordType = (Get-CIPPAzDataTableEntity @Table)


    $Results = try {
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
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        "Failed to set configuration: $($_.Exception.message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Results }
    }
}
