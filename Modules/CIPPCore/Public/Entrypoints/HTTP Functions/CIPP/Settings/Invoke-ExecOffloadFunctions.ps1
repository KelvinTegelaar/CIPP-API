
Function Invoke-ExecOffloadFunctions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $roles = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json).userRoles
    if ('superadmin' -notin $roles) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body       = @{ error = 'You do not have permission to perform this action.' }
            })
        return
    } else {
        $Table = Get-CippTable -tablename 'Config'

        if ($Request.Query.Action -eq 'ListCurrent') {
            $CurrentState = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"
            $CurrentState = if (!$CurrentState) {
                [PSCustomObject]@{
                    OffloadFunctions = $false
                }
            } else {
                [PSCustomObject]@{
                    OffloadFunctions = $CurrentState.state
                }
            }
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = $CurrentState
                })
        } else {
            Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = 'OffloadFunctions'
                RowKey       = 'OffloadFunctions'
                state        = $request.Body.OffloadFunctions
            } -Force

            if ($Request.Body.OffloadFunctions) {
                $Results = 'Enabled Offload Functions'
            } else {
                $Results = 'Disabled Offload Functions'
            }
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{ results = $Results }
                })
        }

    }
}
