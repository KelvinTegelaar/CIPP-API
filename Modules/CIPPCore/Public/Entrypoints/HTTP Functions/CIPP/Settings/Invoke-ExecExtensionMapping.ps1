using namespace System.Net

Function Invoke-ExecExtensionMapping {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $Table = Get-CIPPTable -TableName CippMapping

    if ($Request.Query.List) {
        switch ($Request.Query.List) {
            'Halo' {
                $body = Get-HaloMapping -CIPPMapping $Table
            }

            'NinjaOrgs' {
                $Body = Get-NinjaOneOrgMapping -CIPPMapping $Table
            }

            'NinjaFields' {
                $Body = Get-NinjaOneFieldMapping -CIPPMapping $Table

            }
        }
    }

    try {
        if ($Request.Query.AddMapping) {
            switch ($Request.Query.AddMapping) {
                'Halo' {
                    $body = Set-HaloMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                }

                'NinjaOrgs' {
                    $Body = Set-NinjaOneOrgMapping -CIPPMapping $Table -APIName $APIName -Request $Request
                }

                'NinjaFields' {
                    $Body = Set-NinjaOneFieldMapping -CIPPMapping $Table -APIName $APIName -Request $Request -TriggerMetadata $TriggerMetadata
                }
            }
        }
    } catch {
        Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "mapping API failed. $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    }

    try {
        if ($Request.Query.AutoMapping) {
            switch ($Request.Query.AutoMapping) {
                'NinjaOrgs' {
                    #Push-OutputBinding -Name NinjaProcess -Value @{'NinjaAction' = 'StartAutoMapping' }
                    $Batch = [PSCustomObject]@{
                        'NinjaAction'  = 'StartAutoMapping'
                        'FunctionName' = 'NinjaOneQueue'
                    }
                    $InputObject = [PSCustomObject]@{
                        OrchestratorName = 'NinjaOneOrchestrator'
                        Batch            = @($Batch)
                    }
                    #Write-Host ($InputObject | ConvertTo-Json)
                    $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                    Write-Host "Started permissions orchestration with ID = '$InstanceId'"
                    $Body = [pscustomobject]@{'Results' = 'Automapping Request has been queued. Exact name matches will appear first and matches on device names and serials will take longer. Please check the CIPP Logbook and refresh the page once complete.' }
                }

            }
        }
    } catch {
        Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message "mapping API failed. $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
