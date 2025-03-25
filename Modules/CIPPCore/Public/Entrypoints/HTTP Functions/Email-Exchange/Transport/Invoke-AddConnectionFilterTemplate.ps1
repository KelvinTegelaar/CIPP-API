using namespace System.Net

Function Invoke-AddConnectionFilterTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.ConnectionFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    Write-Host ($request | ConvertTo-Json -Compress)

    try {
        $GUID = (New-Guid).GUID
        $JSON = if ($request.body.PowerShellCommand) {
            Write-Host 'PowerShellCommand'
            $request.body.PowerShellCommand | ConvertFrom-Json
        } else {
            $GUID = (New-Guid).GUID
        ([pscustomobject]$Request.body | Select-Object Name, EnableSafeList, IPAllowList , IPBlockList ) | ForEach-Object {
                $NonEmptyProperties = $_.psobject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name
                $_ | Select-Object -Property $NonEmptyProperties
            }
        }
        $JSON = ($JSON | Select-Object @{n = 'name'; e = { $_.name } }, @{n = 'comments'; e = { $_.comments } }, * | ConvertTo-Json -Depth 10)
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$json"
            RowKey       = "$GUID"
            PartitionKey = 'ConnectionfilterTemplate'
        }
        $Result = "Successfully created Connection Filter Template: $($Request.Body.name) with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Debug'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create Connection Filter Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
