using namespace System.Net

Function Invoke-AddConnectionFilterTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.ConnectionFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    Write-Host ($request | ConvertTo-Json -Compress)

    try {
        $GUID = (New-Guid).GUID
        $JSON = if ($request.body.PowerShellCommand) {
            Write-Host 'PowerShellCommand'
            $request.body.PowerShellCommand | ConvertFrom-Json
        }
        else {
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
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Created Connection Filter Template $($Request.body.name) with GUID $GUID" -Sev 'Debug'
        $body = [pscustomobject]@{'Results' = 'Successfully added template' }

    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create Connection Filter Template: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "ConnectionFilter Template Deployment failed: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
